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

-- What devices actually page through.
--
-- `server_at` cannot do this job alone. now() is the transaction timestamp, so
-- every row written by one push shares a single value, and a page boundary
-- landing inside that group means the next request, which asks for anything
-- after the last value it saw, skips the rest of the group for good. A
-- sequence has no ties, so there is no group to land inside.
--
-- An update has to take a new value or a device already past the old one would
-- never be told, which is why the push function sets it on conflict rather
-- than leaving it alone.
alter table mise_records add column if not exists server_seq bigserial;

create index if not exists mise_records_cursor on mise_records(household_id, server_at);
create index if not exists mise_records_seq on mise_records(household_id, server_seq);

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

alter table mise_deletions add column if not exists server_seq bigserial;

-- A signed in person needs the sequence, not just the table.
--
-- `bigserial` means the column's default is nextval() on a sequence, and
-- nextval is a privilege of its own. Granting insert on the table is not
-- enough: every push is refused with "permission denied for sequence", from a
-- message that names an object nobody wrote by hand and no policy mentions.
--
-- By name through pg_get_serial_sequence rather than by guessing it, because
-- the generated name depends on the table and column and is not worth
-- reproducing in two places.
do $$
declare
  seq text;
begin
  for seq in
    select pg_get_serial_sequence('mise_records', 'server_seq')
    union all
    select pg_get_serial_sequence('mise_deletions', 'server_seq')
  loop
    if seq is not null then
      execute format('grant usage, select on sequence %s to authenticated', seq);
    end if;
  end loop;
end $$;

create index if not exists mise_deletions_cursor on mise_deletions(household_id, server_at);
create index if not exists mise_deletions_seq on mise_deletions(household_id, server_seq);

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

-- A person may add only themselves, and only to a household whose id they
-- already know. The id is a random v4 uuid handed over as an invite code, so
-- knowing it is what grants access, the same way a share link works. Guessing
-- one is not a realistic attack; publishing one is, which is why the app
-- keeps it in the Keychain and never derives it from anything predictable.
drop policy if exists "a person joins a household" on mise_household_members;
create policy "a person joins a household" on mise_household_members
  for insert with check (user_id = auth.uid());

-- Leaving is allowed; removing someone else is not.
drop policy if exists "a person leaves a household" on mise_household_members;
create policy "a person leaves a household" on mise_household_members
  for delete using (user_id = auth.uid());

-- Joining, done by the server rather than by the client.
--
-- The policy above is the whole story in theory: a person may insert a row
-- that names themselves. In practice the client insert was refused by that
-- policy for four rounds of debugging while `mise_whoami()` kept answering
-- with the right account, which is the signature of the insert never being a
-- plain insert at all. PostgREST turns a POST carrying
-- `Prefer: resolution=ignore-duplicates` into an upsert, and an upsert is
-- checked against the update policy too, and there is no update policy here
-- because nothing about a membership row is editable.
--
-- Rather than keep the client guessing at which policy it has to satisfy,
-- the server does the insert itself. This runs as the owner, so no policy
-- applies, and it is safe for exactly one reason: the row it writes is built
-- from `auth.uid()` and not from anything the caller sends. A caller can
-- name any household, which is the point, since knowing the invite code is
-- what joining means. A caller cannot name anybody but themselves.
create or replace function mise_join_household(target uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
begin
  if caller is null then
    raise exception 'Not signed in.' using errcode = '28000';
  end if;

  insert into mise_household_members (household_id, user_id)
  values (target, caller)
  on conflict (household_id, user_id) do nothing;

  return caller;
end;
$$;

revoke all on function mise_join_household(uuid) from public;
grant execute on function mise_join_household(uuid) to authenticated;

drop policy if exists "members read records" on mise_records;
create policy "members read records" on mise_records
  for select using (mise_is_member_of(household_id));

drop policy if exists "members write records" on mise_records;
create policy "members write records" on mise_records
  for insert with check (mise_is_member_of(household_id));

drop policy if exists "members update records" on mise_records;
create policy "members update records" on mise_records
  for update using (mise_is_member_of(household_id)) with check (mise_is_member_of(household_id));

-- `mise_push_deletions` clears the record a tombstone replaces. Without a
-- delete policy that clear-out matches no rows and fails silently, because
-- row level security hides rows from a delete rather than refusing it, so a
-- deleted item would come back the first time a new phone pulled everything.
drop policy if exists "members remove records" on mise_records;
create policy "members remove records" on mise_records
  for delete using (mise_is_member_of(household_id));

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
  -- One row per record before the insert sees it.
  --
  -- Postgres refuses an ON CONFLICT that would touch the same row twice in one
  -- statement, and it refuses it by aborting the whole statement. A payload
  -- that happened to carry a record twice would therefore fail every push that
  -- contained it, forever, with an error about command semantics that says
  -- nothing about what is actually stuck.
  with incoming as (
    select distinct on (household_id, entity, id) *
    from (
      select
        (r->>'household_id')::uuid      as household_id,
        r->>'entity'                    as entity,
        (r->>'id')::uuid                as id,
        r->'fields'                     as fields,
        (r->>'updated_at')::timestamptz as updated_at,
        (r->>'device_id')::uuid         as device_id
      from jsonb_array_elements(payload) as r
    ) flat
    order by household_id, entity, id, updated_at desc
  )
  insert into mise_records (household_id, entity, id, fields, updated_at, server_at, device_id)
  select i.household_id, i.entity, i.id, i.fields, i.updated_at, now_at, i.device_id
  from incoming i
  -- A record a tombstone already covers does not come back.
  --
  -- Without this, deleting something on one phone and pushing from the other
  -- before it has pulled puts the row back: the tombstone removed it, so there
  -- is nothing left for the conflict clause to compare against and the stale
  -- copy inserts cleanly. The phone that deleted it then pulls it in again,
  -- having thrown its own tombstone away as sent.
  where not exists (
    select 1 from mise_deletions d
    where d.household_id = i.household_id
      and d.entity       = i.entity
      and d.record_id    = i.id
      and d.deleted_at  >= i.updated_at
  )
  on conflict (household_id, entity, id) do update
    set fields     = excluded.fields,
        updated_at = excluded.updated_at,
        server_at  = excluded.server_at,
        server_seq = excluded.server_seq,
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
  with incoming as (
    select distinct on (household_id, entity, record_id) *
    from (
      select
        (d->>'household_id')::uuid      as household_id,
        d->>'entity'                    as entity,
        (d->>'record_id')::uuid         as record_id,
        (d->>'deleted_at')::timestamptz as deleted_at,
        (d->>'device_id')::uuid         as device_id
      from jsonb_array_elements(payload) as d
    ) flat
    order by household_id, entity, record_id, deleted_at desc
  ),
  stored as (
    insert into mise_deletions (household_id, entity, record_id, deleted_at, server_at, device_id)
    select i.household_id, i.entity, i.record_id, i.deleted_at, now_at, i.device_id
    from incoming i
    on conflict (household_id, entity, record_id) do update
      set deleted_at = excluded.deleted_at,
          server_at  = excluded.server_at,
          server_seq = excluded.server_seq
      where mise_deletions.deleted_at < excluded.deleted_at
    returning household_id, entity, record_id, deleted_at
  )
  -- A record that has been deleted does not need keeping. Driven off the
  -- deduplicated set rather than off the payload, so a record named twice is
  -- considered once.
  delete from mise_records r
  using incoming i
  where r.household_id = i.household_id
    and r.entity       = i.entity
    and r.id           = i.record_id
    and r.updated_at  <= i.deleted_at;

  return now_at;
end;
$$;

-- Who does the server think is calling?
--
-- Added after a run where every insert was refused by a policy of the form
-- `user_id = auth.uid()` while the app was, as far as it knew, signed in.
-- That has two causes which look identical from the client: the row belongs
-- to another account, or the token is not being accepted and auth.uid() is
-- null. This answers it directly.
--
-- Safe to keep. It returns the caller their own id and nothing else, and an
-- unauthenticated caller gets null, which is exactly what they already know.
create or replace function mise_whoami()
returns uuid
language sql
security invoker
stable
as $$
  select auth.uid();
$$;

grant execute on function mise_whoami() to anon, authenticated;

-- What the server actually holds, per table, for one household.
--
-- Added after 190 recipes sat on a phone for a week while every sync reported
-- success. They had been refused by the tombstone guard above, and nothing
-- anywhere compared what a device holds with what the server took, so the only
-- way it surfaced was somebody noticing a recipe listed twice.
--
-- The push function returns a timestamp and changing that would break every
-- client expecting one, so the comparison gets its own call. Read only,
-- security invoker, so a member sees their own household and nobody else's.
create or replace function mise_household_counts(target uuid)
returns jsonb
language sql
security invoker
stable
as $$
  select coalesce(jsonb_object_agg(entity, n), '{}'::jsonb)
  from (
    select entity, count(*) as n
    from mise_records
    where household_id = target
    group by entity
  ) counted;
$$;

grant execute on function mise_household_counts(uuid) to authenticated;
