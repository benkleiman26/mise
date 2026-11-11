-- Suspected duplicate recipes, by normalised title.
--
-- Read only. It changes nothing and is safe to run as often as you like.
--
-- The theory being tested: recipes saved in Mealime that originally came from
-- NYT Cooking arrived twice, once from each export, and the two copies carry
-- different ids so nothing in the app has ever treated them as the same thing.
with recipes as (
  select
    r.id,
    r.fields->>'title'                             as title,
    r.fields->>'sourceType'                        as source,
    nullif(r.fields->>'sourceURL', '')             as url,
    nullif(r.fields->>'imageURL', '')              as image,
    r.fields->>'createdAt'                         as created,
    -- lowercase, strip punctuation, collapse spaces, so "Crunchy Roll Bowls"
    -- and "Crunchy-Roll Bowls" land on the same key
    regexp_replace(lower(trim(r.fields->>'title')), '[^a-z0-9]+', ' ', 'g') as key
  from mise_records r
  where r.entity = 'recipe'
    -- anything the app has deleted does not count as a copy
    and not exists (
      select 1 from mise_deletions d
      where d.household_id = r.household_id
        and d.entity = 'recipe'
        and d.record_id = r.id
    )
)
select
  key,
  count(*)                              as copies,
  array_agg(distinct source)            as sources,
  array_agg(title order by created)     as titles,
  count(image) filter (where image is not null) as with_photo,
  array_agg(id order by created)        as ids
from recipes
group by key
having count(*) > 1
order by copies desc, key;
