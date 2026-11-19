-- Recipes with no ingredients, and whether a complete namesake exists.
--
-- Read only.
--
-- These break meal planning. A recipe with no ingredient records looks
-- ordinary in the library and on the plan and contributes nothing to the
-- grocery list, without saying so.
--
-- `safe_to_delete` is the column that matters. True means another recipe with
-- the same title does have ingredients, so this one is a shell beside a good
-- copy and nothing is lost. False means this is the only copy of that recipe
-- and deleting it deletes the recipe.
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
)
select
  c.fields->>'title' as title,
  c.id,
  c.ingredients,
  exists (
    select 1 from counted other
    where other.key = c.key and other.id <> c.id and other.ingredients > 0
  ) as safe_to_delete
from counted c
where c.ingredients = 0
order by safe_to_delete desc, title;
