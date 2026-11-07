# Android

Asked on 2026-11-07: what would it take to run Mise on Android, with an iPhone
and an Android phone sharing one household?

## The short answer

The server needs nothing. The protocol is genuinely client neutral and was
built that way on purpose: four columns and a `jsonb` blob, so the two phones
in a household need not run the same version (`supabase/schema.sql:12-18`). A
Kotlin client can join the same household as a live iPhone with no schema
change, no migration and no new endpoint. Same project URL, same publishable
key, its own account, one POST to `mise_join_household`.

What is not ready is this side. The wire format exists only as Swift source.
There is no schema, no spec, no golden fixture, and the only sync tests drive
an in-memory fake that passes structs around and never serialises anything, so
the encoding contract is untested by construction. A second client written
correctly against idiomatic Kotlin defaults is wrong in five places at once,
and in every one of them it is wrong by being right. None of them raise an
error on either side. The first symptom would be a shared list with two of
everything, noticed in a shop.

So the work is not "write an Android app". It is: write the contract down,
make it checkable, then write an Android app.

## Fix first, while there is only one platform

These are not Android work. They are existing bugs, and four of them change
how ids are derived, which is far cheaper to migrate with one client than two.

**Confirmed by reading the code:**

1. **`value(from:)` tests `Bool` before `Int`**
   (`Mise/Sync/SupabaseSyncClient.swift:221`). `JSONSerialization` returns
   `NSNumber` for JSON numbers, and an `NSNumber` holding 0 or 1 bridges to
   `Bool`. So `jsonb 1` decodes as `.boolean(true)`, and `integer(_:)` at
   `SyncMapper.swift:746` accepts only `.integer` and `.number`, so it returns
   nil. Every integer field whose value is 0 or 1 fails to arrive: `position`
   on ingredients, steps, planned meals and grocery items, `servings`,
   `weekStartsOn`, `timesCooked`, `prepMinutes`, `cookMinutes`. For a record
   built fresh on the receiving side the fallback is `?? 0`
   (`SyncMapper.swift:443`), so an ingredient at position 1 lands at position 0
   and the order of a synced recipe is quietly wrong. **This is live between
   two iPhones today.** The fix is to test `CFGetTypeID(number) ==
   CFBooleanGetTypeID()` rather than relying on the bridge.

2. **The pull cursor advances over rows that did not decode**
   (`SupabaseSyncClient.swift:63-66`, `SyncEngine.swift:219`). The comment says
   this is deliberate, and for one client it is defensible: a row this version
   cannot read is passed over rather than waited on forever. With a second
   client it stops being defensible, because every encoding disagreement
   becomes permanent and silent rather than a retry. Nothing ever comes back
   for that row. Decide this one consciously before there are two clients.

**Found by the survey, worth checking:**

3. **`StableID.day()` reads `Calendar.current`**
   (`Mise/Domain/Services/StableID.swift:92-95`), which is the user's region
   calendar. An iPhone set to a Buddhist or Japanese calendar already derives
   meal plan ids no other phone agrees with. `java.time` is always ISO, so
   Android would match only the Gregorian users. Pin it to
   `Calendar(identifier: .gregorian)` with an explicit timezone.

4. **The v5 hash is over raw UTF-8 with no Unicode normalisation**
   (`StableID.swift:114`). "jalapeno" with a precomposed enye and the same word
   decomposed hash to different UUIDs, while Swift's own `==` calls them equal.
   So the app's dedupe says "same line" and `StableID` says "different row".
   NFC-normalise before hashing.

5. **The within-aisle sort uses ICU locale collation**
   (`Mise/Domain/Services/ListGenerator.swift:325`,
   `localizedCaseInsensitiveCompare`). That order decides the persisted
   `position` and the `tieBreak` assignment order at
   `GroceryListStore.swift:118-138`. No Android comparator reproduces it. Both
   platforms should use one fixed, explicit comparator.

6. **The `fields` blob is replaced wholesale** (`schema.sql:273` sets `fields =
   excluded.fields`) while `SyncTypes.swift:16-19` promises unknown fields are
   kept and written back untouched. That promise is not implemented anywhere.
   Until it is, any client that lags a version strips every field it does not
   know from the other phone's records. This is the single change that turns a
   partial second client from destructive into merely incomplete.

7. **Applying a received deletion manufactures a local tombstone owned by this
   device** (`Mise/Domain/Repositories/SwiftDataRepository.swift:41-65`), which
   is then pushed back.

Then: write the contract down (the entity names, the field names and types, the
66 enum raw values, the date format, the `StableID` name strings) and commit
golden fixtures generated from the Swift side. Roughly a day, and it converts
most of the hazard list from "hope the two agree" into a failing test.

## The four ways to do it

Costed for one part-time developer working with an AI assistant.

**A separate native Android app** speaking the same protocol. iOS untouched.
8 to 12 weeks to something testable that joins a household read-mostly. 16 to
26 weeks to a client you would put on a spouse's phone. The real cost is not
the port, it is the standing obligation to implement every future feature
twice, in exact agreement, against a spec that only exists as Swift source.

**Kotlin Multiplatform** over the shared core. 24 to 40 weeks, of which the
first 12 to 20 produce nothing anybody can open. It is the right long-run
answer to "how do these two stay in agreement forever", but collecting the
dividend means replacing SwiftData first, on the one device holding a year of
real household data, with no versioned schema to migrate through. Wrong trade
for a side project. The narrow version, a KMP module holding only pure
functions over primitives, is 2 to 4 weeks and shares about 400 lines.

**Rewrite both in Flutter.** 12 to 20 weeks, and it spends the project's best
debugging asset: a known-correct peer to diff against. Every sync scar in this
repo was diagnosable because one side was right. Don't.

**A web app instead.** 6 to 10 weeks, lowest risk, and it serves desktop too.
But scoped honestly it is a companion that shops and ticks, not an Android
client: generating a list, importing a recipe and the recipe library itself
live in the 2,900 lines it would skip.

## The question that decides it

Who is the Android user?

If they are a second phone in a household that already has an iPhone, the web
companion is the best trade here by a distance, and it is weeks rather than
months.

If they are a household with no iPhone in it, the companion gives them
literally nothing: an empty database it refuses to seed, no parser, no
generator, no catalogue. That case needs a real client, which means the
separate native Android app, and months.

Answer that before any of the rest.
