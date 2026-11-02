-- Mise sync schema.
--
-- Run this once in the Supabase SQL editor:
--   Dashboard -> SQL Editor -> New query -> paste -> Run
--
-- Every table, index and function here is prefixed `mise_`, so this can live
-- inside a Supabase project that is already being used for something else.
-- Free plans allow two projects per organisation and the owner was out of
-- them; sharing a database with an unrelated app is fine when the names cannot
-- collide and row level security is on, which it is.
--
-- The shape is deliberately boring. Every table is the same four columns plus
-- a JSON blob, because the two phones in a household will not be running the
-- same version of the app: one updates on Tuesday and the other on Friday. A
-- column per field would mean the older phone refusing a row it could have
-- mostly understood, and a migration every time the app learns a new field.
-- Postgres is holding records for one household, not answering questions about
-- them.
--
-- Conflicts are settled by updated_at, last writer wins, per record. That is
-- right here because the records are small and separate: two people ticking
-- different items off a list do not collide, and the case where they edit the
-- same recipe within seconds of each other is rare enough to accept losing the
-- earlier edit.

create extension if not exists "pgcrypto";

-- Who is in which household. A person is in exactly one, in this version.
create table if not exists mise_household_members (
  household_id  uuid        not null,
  user_id       uuid        not null references auth.users(id) on delete cascade,
  joined_at     timestamptz not null default now(),
  primary key (household_id, user_id)
);

create index if not exists mise_household_members_user on mise_household_members(user_id);

-- Every synced record, whatever table it came from.
create table if not exists mise_records (
  household_id  uuid        not null,
  entity        text        not null,
  id            uuid        not null,
  fields        jsonb       not null,
  updated_at    timestamptz not null,
  -- The server's own clock, which is what devices page through. Device clocks
  -- disagree, sometimes by minutes, and a cursor taken from the wrong clock
  -- silently loses changes.
  server_at     timestamptz not null default now(),
  device_id     uuid        not null,
  primary key (household_id, entity, id)
);

create index if not exists mise_records_cursor on mise_records(household_id, server_at);

-- Deletions, because the absence of a row is not information.
create table if not exists mise_deletions (
  household_id  uuid        not null,
  entity        text        not null,
  record_id     uuid        not null,
  deleted_at    timestamptz not null,
  server_at     timestamptz not null default now(),
  device_id     uuid        not null,
  primary key (household_id, entity, record_id)
);

create index if not exists mise_deletions_cursor on mise_deletions(household_id, server_at);

-- Row level security. Without this every signed in user of every Supabase
-- project could read this household's data, and the anon key is published in
-- the app.
alter table mise_household_members enable row level security;
alter table mise_records           enable row level security;
alter table mise_deletions         enable row level security;

create or replace function mise_is_member_of(target uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from mise_household_members
    where household_id = target and user_id = auth.uid()
  );
$$;

drop policy if exists "members read their household" on mise_household_members;
create policy "members read their household" on mise_household_members
  for select using (mise_is_member_of(household_id));

drop policy if exists "a person joins a household" on mise_household_members;
create policy "a person joins a household" on mise_household_members
  for insert with check (user_id = auth.uid());

drop policy if exists "members read records" on mise_records;
create policy "members read records" on mise_records
  for select using (mise_is_member_of(household_id));

drop policy if exists "members write records" on mise_records;
create policy "members write records" on mise_records
  for insert with check (mise_is_member_of(household_id));

drop policy if exists "members update records" on mise_records;
create policy "members update records" on mise_records
  for update using (mise_is_member_of(household_id)) with check (mise_is_member_of(household_id));

drop policy if exists "members read deletions" on mise_deletions;
create policy "members read deletions" on mise_deletions
  for select using (mise_is_member_of(household_id));

drop policy if exists "members write deletions" on mise_deletions;
create policy "members write deletions" on mise_deletions
  for insert with check (mise_is_member_of(household_id));

drop policy if exists "members update deletions" on mise_deletions;
create policy "members update deletions" on mise_deletions
  for update using (mise_is_member_of(household_id)) with check (mise_is_member_of(household_id));

-- Upsert that refuses to go backwards.
--
-- Two phones pushing the same record out of order must not leave the older
-- copy on top, and a retry of a push that already succeeded must not undo a
-- newer edit. The where clause is what makes a push safe to repeat.
create or replace function mise_push_records(payload jsonb)
returns timestamptz
language plpgsql
security invoker
as $$
declare
  now_at timestamptz := now();
begin
  insert into mise_records (household_id, entity, id, fields, updated_at, server_at, device_id)
  select
    (r->>'household_id')::uuid,
    r->>'entity',
    (r->>'id')::uuid,
    r->'fields',
    (r->>'updated_at')::timestamptz,
    now_at,
    (r->>'device_id')::uuid
  from jsonb_array_elements(payload) as r
  on conflict (household_id, entity, id) do update
    set fields     = excluded.fields,
        updated_at = excluded.updated_at,
        server_at  = excluded.server_at,
        device_id  = excluded.device_id
    where mise_records.updated_at < excluded.updated_at;

  return now_at;
end;
$$;

create or replace function mise_push_deletions(payload jsonb)
returns timestamptz
language plpgsql
security invoker
as $$
declare
  now_at timestamptz := now();
begin
  insert into mise_deletions (household_id, entity, record_id, deleted_at, server_at, device_id)
  select
    (d->>'household_id')::uuid,
    d->>'entity',
    (d->>'record_id')::uuid,
    (d->>'deleted_at')::timestamptz,
    now_at,
    (d->>'device_id')::uuid
  from jsonb_array_elements(payload) as d
  on conflict (household_id, entity, record_id) do update
    set deleted_at = excluded.deleted_at,
        server_at  = excluded.server_at
    where mise_deletions.deleted_at < excluded.deleted_at;

  -- A record that has been deleted does not need keeping.
  delete from mise_records r
  using jsonb_array_elements(payload) as d
  where r.household_id = (d->>'household_id')::uuid
    and r.entity       = d->>'entity'
    and r.id           = (d->>'record_id')::uuid
    and r.updated_at   <= (d->>'deleted_at')::timestamptz;

  return now_at;
end;
$$;
