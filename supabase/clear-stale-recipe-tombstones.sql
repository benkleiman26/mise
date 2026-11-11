-- Clear the tombstones that are holding the library down.
--
-- The symptom: 447 recipes on a phone, 257 on the server, and more tombstones
-- than records for all three recipe tables.
--
-- The cause: a re-import used to delete each recipe and rebuild it, and every
-- delete wrote a tombstone. The rebuilt recipe keeps its derived id, so the
-- tombstone and the replacement name the same record. `mise_push_records`
-- refuses any record a tombstone covers with `deleted_at >= updated_at`
-- (schema.sql:265), and an imported recipe's `updatedAt` is from the day it
-- was imported while the tombstone is from the day of the re-import. So the
-- comparison holds forever and those recipes can never be pushed again.
--
-- `replace(_:)` fixed the cause, so no new tombstones of this kind are
-- written. This clears the ones already there.
--
-- Why it is safe: a tombstone only matters while some phone still holds the
-- record it names. A recipe genuinely deleted is gone from both phones, so
-- removing its tombstone resurrects nothing, because nothing is left to push.
-- The one exception is a recipe deleted on one phone whose deletion never
-- reached the other; that one comes back and can be deleted again.
--
-- Run it, then raise the shared set version in SyncEngine so both phones
-- resend everything, then sync on both.

begin;

select entity, count(*) as "tombstones before"
from mise_deletions
where entity in ('recipe', 'ingredient', 'recipeStep')
group by entity
order by entity;

delete from mise_deletions
where entity in ('recipe', 'ingredient', 'recipeStep');

select entity, count(*) as "records now"
from mise_records
where entity in ('recipe', 'ingredient', 'recipeStep')
group by entity
order by entity;

commit;
