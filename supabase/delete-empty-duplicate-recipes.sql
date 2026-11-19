-- Remove the shell recipes that sit beside a complete copy.
--
-- CHANGES DATA. Run find-empty-recipes.sql first and read the
-- `safe_to_delete` column: this deletes exactly the rows where that is true,
-- which are the ones whose title also belongs to a recipe that does have
-- ingredients. A recipe that is only a shell is left alone, because deleting
-- it would delete the recipe.
--
-- It writes tombstones rather than removing rows. A row deleted here and not
-- tombstoned comes straight back the next time either phone pushes, since the
-- phones still hold their own copies. The tombstone is what tells them to let
-- go, and the push function removes the record itself when it sees one.
begin;

with live as (
  select r.*,
    regexp_replace(lower(trim(r.fields->>'title')), '[^a-z0-9]+', ' ', 'g') as key
  from mise_records r
  where r.entity = 'recipe'
    and not exists (
      select 1 from mise_deletions d
      where d.household_id = r.household_id and d.entity = 'recipe' and d.record_id = r.id
    )
),
counted as (
  select l.*,
    (select count(*) from mise_records i
      where i.household_id = l.household_id
        and i.entity = 'ingredient'
        and lower(i.fields->>'recipeID') = l.id::text) as ingredients
  from live l
),
doomed as (
  select c.household_id, c.id
  from counted c
  where c.ingredients = 0
    and exists (
      select 1 from counted other
      where other.key = c.key and other.id <> c.id and other.ingredients > 0
    )
)
insert into mise_deletions (household_id, entity, record_id, deleted_at, device_id)
select household_id, 'recipe', id, now(), '00000000-0000-0000-0000-000000000000'::uuid
from doomed
on conflict (household_id, entity, record_id) do nothing;

delete from mise_records r
where r.entity = 'recipe'
  and exists (
    select 1 from mise_deletions d
    where d.household_id = r.household_id
      and d.entity = 'recipe'
      and d.record_id = r.id
      and d.deleted_at >= r.updated_at
  );

select count(*) as "shells removed" from mise_deletions where device_id = '00000000-0000-0000-0000-000000000000';

commit;
