-- Recipes with no ingredients.
--
-- Read only.
--
-- These are what breaks meal planning. A recipe with no ingredient records
-- looks ordinary in the library and on the plan, and contributes nothing to
-- the grocery list, without saying so. Three recipes planned, one recipe's
-- worth of shopping.
select
  r.fields->>'title'                        as title,
  r.id,
  (r.fields->>'summary' is not null
    and r.fields->>'summary' <> '')         as has_summary,
  (r.fields->>'imageURL' is not null)       as has_photo,
  r.fields->>'sourceType'                   as source,
  left(r.device_id::text, 8)                as wrote_it,
  r.updated_at
from mise_records r
where r.entity = 'recipe'
  and not exists (
    select 1 from mise_deletions d
    where d.household_id = r.household_id
      and d.entity = 'recipe'
      and d.record_id = r.id
  )
  and not exists (
    select 1 from mise_records i
    where i.household_id = r.household_id
      and i.entity = 'ingredient'
      and lower(i.fields->>'recipeID') = r.id::text
  )
order by title;
