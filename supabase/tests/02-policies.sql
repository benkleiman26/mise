-- The policies, exercised as a signed in person rather than as the owner.
--
-- Worth having because four rounds of debugging went into a policy failure
-- that every superuser query said was impossible: the owner bypasses row level
-- security, so testing as the owner tests nothing. Run after 01-push.sql,
-- which defines check_that.
\set ON_ERROR_STOP on
grant usage on schema public, auth to authenticated, anon;
grant select on auth.users to authenticated, anon;
grant all on all tables in schema public to authenticated;
grant all on all sequences in schema public to authenticated;

insert into auth.users (id) values
  ('11111111-1111-1111-1111-111111111111'),
  ('22222222-2222-2222-2222-222222222222') on conflict do nothing;
truncate mise_records, mise_deletions, mise_household_members;

-- Ben signs in and joins a household nobody is in yet.
set role authenticated;
set request.jwt.claim.sub = '11111111-1111-1111-1111-111111111111';
select check_that('the server knows who is calling',
  auth.uid() = '11111111-1111-1111-1111-111111111111');
select mise_join_household('dddddddd-0000-0000-0000-00000000000f');
select check_that('joining a brand new household works',
  (select count(*) = 1 from mise_household_members));

select mise_push_records('[
 {"household_id":"dddddddd-0000-0000-0000-00000000000f","entity":"groceryItem","id":"bbbbbbbb-0000-0000-0000-000000000009",
  "fields":{"displayName":"lemons"},"updated_at":"2026-01-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000001"}
]'::jsonb);
select check_that('a member can push', (select count(*) = 1 from mise_records));

-- Megan signs in on her own phone and joins with the invite code.
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
select mise_join_household('dddddddd-0000-0000-0000-00000000000f');
select check_that('a second person can join with the code',
  (select count(*) = 2 from mise_household_members));
select check_that('and sees the household list', (select count(*) = 1 from mise_records));

-- A stranger who knows nothing must get nothing.
set request.jwt.claim.sub = '22222222-2222-2222-2222-222222222222';
do $$ begin
  begin
    perform mise_push_records('[
     {"household_id":"eeeeeeee-0000-0000-0000-000000000099","entity":"groceryItem","id":"bbbbbbbb-0000-0000-0000-000000000010",
      "fields":{"displayName":"not mine"},"updated_at":"2026-01-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000001"}
    ]'::jsonb);
    raise exception 'FAIL  pushing into a household you are not in was allowed';
  exception when insufficient_privilege then
    raise notice 'PASS  pushing into a household you are not in is refused';
  end;
end $$;

-- And must not be able to add somebody else to a household.
do $$ begin
  begin
    insert into mise_household_members (household_id, user_id)
    values ('dddddddd-0000-0000-0000-00000000000f', '11111111-1111-1111-1111-111111111111');
    raise exception 'FAIL  adding a different person was allowed';
  exception
    when insufficient_privilege then raise notice 'PASS  adding somebody else is refused';
    when unique_violation then raise notice 'PASS  adding somebody else is refused (already present)';
  end;
end $$;

reset role;
select check_that('the household is exactly its two people',
  (select count(*) = 2 from mise_household_members));
