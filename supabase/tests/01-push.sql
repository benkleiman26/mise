\set ON_ERROR_STOP on
create or replace function check_that(label text, ok boolean) returns void language plpgsql as $$
begin
  if ok then raise notice 'PASS  %', label;
  else raise exception 'FAIL  %', label; end if;
end $$;

insert into auth.users (id) values ('11111111-1111-1111-1111-111111111111') on conflict do nothing;
truncate mise_records, mise_deletions, mise_household_members;

-- 1. The same record twice in one payload must not abort the push.
select mise_push_records('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"groceryItem","id":"bbbbbbbb-0000-0000-0000-000000000001",
  "fields":{"displayName":"old"},"updated_at":"2026-01-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000001"},
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"groceryItem","id":"bbbbbbbb-0000-0000-0000-000000000001",
  "fields":{"displayName":"new"},"updated_at":"2026-02-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000001"}
]'::jsonb);
select check_that('a record named twice in one payload is stored once, newest wins',
  (select count(*) = 1 and max(fields->>'displayName') = 'new' from mise_records));

-- 2. An older push must not overwrite a newer row.
select mise_push_records('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"groceryItem","id":"bbbbbbbb-0000-0000-0000-000000000001",
  "fields":{"displayName":"stale"},"updated_at":"2025-01-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000002"}
]'::jsonb);
select check_that('an older push does not go backwards',
  (select fields->>'displayName' = 'new' from mise_records));

-- 3. An update must take a new sequence value or a device already past the old one never hears.
create temp table seq_before as select server_seq from mise_records;
select mise_push_records('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"groceryItem","id":"bbbbbbbb-0000-0000-0000-000000000001",
  "fields":{"displayName":"newer"},"updated_at":"2026-03-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000002"}
]'::jsonb);
select check_that('an updated record moves to the end of the queue',
  (select r.server_seq > b.server_seq from mise_records r, seq_before b));

-- 4. Two tombstones for one record in one payload must not abort.
select mise_push_deletions('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"groceryItem","record_id":"bbbbbbbb-0000-0000-0000-000000000001",
  "deleted_at":"2026-04-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000001"},
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"groceryItem","record_id":"bbbbbbbb-0000-0000-0000-000000000001",
  "deleted_at":"2026-05-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000001"}
]'::jsonb);
select check_that('a record named twice in one deletion payload is one tombstone',
  (select count(*) = 1 from mise_deletions));
select check_that('the tombstone takes the record with it',
  (select count(*) = 0 from mise_records));

-- 5. The other phone pushing its stale copy must not resurrect it.
select mise_push_records('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"groceryItem","id":"bbbbbbbb-0000-0000-0000-000000000001",
  "fields":{"displayName":"back from the dead"},"updated_at":"2026-03-15T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000003"}
]'::jsonb);
select check_that('a stale copy pushed after the tombstone stays dead',
  (select count(*) = 0 from mise_records));

-- 6. But deliberately remaking it afterwards must work.
select mise_push_records('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"groceryItem","id":"bbbbbbbb-0000-0000-0000-000000000001",
  "fields":{"displayName":"added again on purpose"},"updated_at":"2026-06-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000003"}
]'::jsonb);
select check_that('adding it again on purpose beats the tombstone',
  (select count(*) = 1 from mise_records));

-- 7. An empty payload is not an error.
select mise_push_records('[]'::jsonb);
select mise_push_deletions('[]'::jsonb);
select check_that('an empty payload does nothing quietly', true);

-- 8. Counting what the household holds, which is how a phone finds out that
--    something it pushed was refused.
select mise_push_records('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"recipe","id":"bbbbbbbb-0000-0000-0000-000000000002",
  "fields":{"title":"one"},"updated_at":"2026-06-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000003"},
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"recipe","id":"bbbbbbbb-0000-0000-0000-000000000003",
  "fields":{"title":"two"},"updated_at":"2026-06-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000003"}
]'::jsonb);
select check_that('counts report each table separately',
  (select mise_household_counts('aaaaaaaa-0000-0000-0000-000000000001')
          = '{"recipe": 2, "groceryItem": 1}'::jsonb));

-- A refused push is exactly the case this exists to make visible: the count
-- does not move, while the push itself reports nothing wrong.
select mise_push_deletions('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"recipe","record_id":"bbbbbbbb-0000-0000-0000-000000000003",
  "deleted_at":"2026-07-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000003"}
]'::jsonb);
select mise_push_records('[
 {"household_id":"aaaaaaaa-0000-0000-0000-000000000001","entity":"recipe","id":"bbbbbbbb-0000-0000-0000-000000000003",
  "fields":{"title":"two"},"updated_at":"2026-06-01T00:00:00Z","device_id":"cccccccc-0000-0000-0000-000000000003"}
]'::jsonb);
select check_that('a refused push leaves the count where it was',
  (select (mise_household_counts('aaaaaaaa-0000-0000-0000-000000000001')->>'recipe')::int = 1));

select check_that('counting a household with nothing in it is an empty object, not null',
  (select mise_household_counts('aaaaaaaa-0000-0000-0000-00000000ffff') = '{}'::jsonb));
