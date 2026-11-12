-- Suspected duplicate recipes, by normalised title.
--
-- Read only. It changes nothing and is safe to run as often as you like.
--
-- Run this only when the phones have finished syncing: before the stale
-- tombstones were cleared the server held 257 of 447 recipes, and a query over
-- a library with 190 of it missing finds nothing and proves nothing.
--
-- The columns after the counts are there to say what made the copies. A copy
-- with the same photo but no summary and no times did not come from a second
-- import of the same page: an importer that got far enough to download the
-- picture would have had the text too. It looks instead like a record written
-- by something that had only some of the fields.
with recipes as (
  select
    r.id,
    r.fields->>'title'                     as title,
    r.fields->>'sourceType'                as source,
    nullif(r.fields->>'sourceURL', '')     as url,
    nullif(r.fields->>'imageURL', '')      as image,
    nullif(r.fields->>'summary', '')       as summary,
    coalesce((r.fields->>'prepMinutes')::int, 0)
      + coalesce((r.fields->>'cookMinutes')::int, 0) as minutes,
    r.fields->>'createdAt'                 as created,
    r.updated_at,
    r.device_id,
    regexp_replace(lower(trim(r.fields->>'title')), '[^a-z0-9]+', ' ', 'g') as key
  from mise_records r
  where r.entity = 'recipe'
    and not exists (
      select 1 from mise_deletions d
      where d.household_id = r.household_id
        and d.entity = 'recipe'
        and d.record_id = r.id
    )
)
select
  r.key,
  count(*) over (partition by r.key)              as copies,
  r.id,
  r.source,
  (r.summary is not null)                         as has_summary,
  r.minutes,
  (r.image is not null)                           as has_photo,
  (r.url is not null)                             as has_url,
  left(r.device_id::text, 8)                      as wrote_it,
  r.created,
  r.updated_at,
  (select count(*) from mise_records i
    where i.entity = 'ingredient'
      and lower(i.fields->>'recipeID') = r.id::text)     as ingredients
from recipes r
where r.key in (select key from recipes group by key having count(*) > 1)
order by r.key, r.created;
