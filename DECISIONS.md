# Decisions

Choices made while building that the spec did not settle. Section 11 asks for
the simplest option that fits the principles in section 2, recorded here, with
work continuing rather than blocking.

Newest last.

## The spec is not mirrored into the repository

`SPEC.md` links to the Google Doc rather than copying it. The document is under
active revision. A copy would drift and the repository would end up with two
specs that disagree. The link is the single source of truth, as the document
itself asks.

## The Mealime export rescues raw responses first, then normalizes separately

Section 5.7 asks for one JSON file per recipe. The export is split into two
commands instead: `export` writes every API response to `raw/` exactly as the
server sent it, and `normalize` turns those files into the documented shape.

The reason is the deadline. Mealime deletes all account data on 2026-10-21. If
an assumption about the JSON turns out to be wrong, the normalizer can be fixed
and re-run against the saved raw files in November. Re-fetching in November is
not possible. Parsing mistakes are recoverable, missing data is not.

## The export probes for endpoints instead of hard coding them

Mealime's v2 API is not publicly documented and cannot be tested without a live
account, which the build environment does not have. The script tries a list of
plausible routes and auth schemes, reports what answered, and writes the result
to `raw/_discovery.json`. It then uses whatever was found.

A hard coded route that turned out to be wrong would fail at the worst moment,
close to the deadline, with no way to tell why.

## The export does not parse ingredient text

Quantity strings stay exactly as Mealime wrote them, including awkward ones like
`2 (15 oz) cans`. The app's `IngredientParser` handles them later, which is the
same parser used for URL imports, with one review screen for the lines it is
unsure about.

Parsing in the export script would mean two parsers to keep in agreement, and
the export script is throwaway while the app parser is not.

## Recipe provenance is assumed to be Mealime's unless there is a signal

Section 5.7 draws a line between recipes the user imported themselves, which
travel in full, and recipes Mealime wrote, which travel as a reference only.
Nothing in the data states which is which, so the export infers it from the
collection the recipe appeared in, the presence of a source URL, and any
ownership fields.

When the signals are absent the export assumes Mealime wrote it. That is the
choice that withholds rather than copies. Each recipe carries the reasoning in
`provenance_reasons` so a wrong call is visible rather than silent, and
`--include-mealime-content` produces a complete private copy for the owner.

## The interchange format is versioned from the start

`mealime-export.json` declares `format` and `version`. People will save these
files before the shutdown and import them months later, so the reader has to be
able to recognize an old file. Changes to a field's meaning bump the version
rather than being made in place.

## Images are downloaded, not just referenced

The spec does not ask for this. The rescued JSON references images by URL on
Mealime's servers, and those URLs stop working when the service does, so a
rescue that keeps only links loses every photo on 2026-10-21.

`npm run images` is a separate command rather than part of the export, because
it is slow, it is the part most likely to be interrupted, and it should be
resumable on its own. No auth header is sent when fetching images: they sit on
third party hosts, including blogs a user imported from, and the Mealime token
has no business going there.

## The tool ships in the main repository rather than its own

Section 9 asks for the export script to be public so other Mealime users can run
it before the shutdown. The `mise` repository is public, so the script is
already public at `tools/mealime-export/` and a second repository would be one
more thing to keep in sync for no gain.

If Mise later needs to go private, the tool moves out then.

## The rescue runs in the browser, because there is no API

Section 5.7 says to pull the data from `api.mealime.com/api/v2` with an auth
token. There is no such API. A capture of the web app's own network traffic on
2026-09-14 showed three requests in total: one analytics beacon and two fetches
of `cdn-recipes.mealime.com/<uuid>.json`, sent with no authentication headers.
`my.mealime.com` is server rendered, so the recipe list is in the page HTML.

So `browser/rescue.js` is the primary path: it harvests recipe ids from the
pages the user visits, fetches each recipe from the CDN, and downloads one file.
No token is needed anywhere, which also makes it far easier for a stranger to
run before the shutdown.

The Node code is unchanged in shape and still does the normalizing. The browser
produces raw recipe JSON, `browser/convert.mjs` lays it out the way the API path
would have, and `npm run normalize` runs exactly as before. Splitting rescue
from normalize is what made this survivable: only the fetching had to be
rewritten.

The API client is kept rather than deleted. It costs nothing, it is tested, and
if Mealime does have an internal API on another host it is a small edit to point
at it.

## Dependencies

None so far. The export tool is plain Node with the built in test runner, and
Node 20 is the only requirement.

## The rescue reads the web app's state instead of scraping pages

The earlier browser rescue scraped every uuid out of page HTML and got 295 of
them, then hit 403 on all of them. The uuids were not recipes. S3 answers 403,
not 404, for keys it will not list, so the wall looked like an auth problem
and was really a wrong-id problem.

The web app is a React app that loads the entire account with one call
(`api/v2/get_user`, so there is an API, just not one worth probing) and keeps
the result in component state. `browser/rescue-state.js` walks the React tree,
takes that object, strips the secrets, and fetches the 54 favourites from
`cdn-recipes.mealime.com` by their `published_recipe_uuid`, all of which
answered 200 with no credentials. The user's own 159 recipes are inline in
the account object, so they need no fetch at all.

This is fragile in the way any dependence on React internals is, and Mealime
will not change its bundle again before it shuts down, so that is acceptable.

## Images are rescued through the browser, as a zip

`cdn-uploads.mealime.com` refuses everything that is not the owner's browser
(403 from the cloud, connection refused from the laptop VM) and sends no CORS
headers, so pages on my.mealime.com cannot fetch it either. A tab opened on
that origin can fetch same-origin, so `browser/rescue-images.js` runs there,
packs the files into a stored zip written by hand (no third party script
loaded into the page), and `images --from-zip` feeds that zip to the same
download code through its `fetchImpl` hook. Chrome only honors a download
from a non-HTML document on a real click, which is why the script draws a
button instead of clicking for you.

## Preferences are decoded from observed ids

The account's profile stores `recipe_type_id: 4` and `dislike_ids: [10]`; the
lookup tables live only in the app bundle. The settings page for this account
showed Pescetarian, olives, 4 servings, US units on 2026-09-14, so
`convert.mjs` carries exactly those id to name pairs and leaves any other id
labeled as an id rather than guessing.

## The NYT export collects in the browser and converts in Node

Same split as the Mealime rescue, for the same reason: the collecting depends on
a page structure nobody has verified, and the converting does not. When NYT's
markup turns out to differ from what was assumed, only `browser/collect.js`
changes, and `src/convert.mjs` keeps its tests.

The collector tries three strategies in order and reports which fired: the
Next.js hydration payload, the rendered DOM, and raw matching of
`/recipes/<id>-<slug>` anywhere in the markup. That last one is crude and will
work even if the first two are wrong, which is the point. `__nyt.probe()` exists
so the first move on an unknown page is to look rather than to guess, which is
the lesson from spending a day on a Mealime API that did not exist.

## Recipe Box folders become tags, but status folders do not

Section 5.6a asks for folders to be mapped to tags. Some folder names describe a
status rather than a topic: Cooked Recipes, Recipe Box, Saved. Those become the
`cooked` flag or nothing at all, never a tag, because a tag named "cooked" would
compete with the real cooked count the app keeps.

Filler words are dropped too, so "Easy Kid-Friendly Recipes" becomes
"kid friendly" rather than "easy kid friendly recipes". Tags are flat and
lowercase per section 5.1.

## The bookmarks parser lives in tools, not just in the app

Section 8 lists two tools, and this adds a third, `tools/bulk-import/`. The
bulk URL import is an app feature and stays one; what lives here is the Netscape
bookmarks parser and an inventory built on it.

The format is awkward (invalid HTML, missing closing tags, folders implied by
nesting) and getting it wrong is silent: a mis-parsed folder stack quietly files
recipes under the wrong tag. Writing it in Node first means it is tested
exhaustively where tests are cheap, and Phase 4 ports known-good logic against
the same fixture rather than starting from the spec.

The inventory also answers a planning question that cannot wait for Phase 4: how
many of the bookmarks sit on hosts without JSON-LD, which is what sizes the AI
extraction work in Phase 4b.

## Resource JSON is validated in Node, because nothing else can check it

`Mise/Resources/canonical_items.json` and `seed_recipes.json` decide where every
grocery item lands, and they fail quietly: a duplicate alias files an ingredient
under the wrong aisle, an unknown unit stops a merge, and neither is a crash.

There is no Swift toolchain in the cloud environment, so `tools/resource-lint`
is the only check these files get before they reach a phone. It also encodes
rules the app cannot easily assert, such as section 11's ban on em dashes and
section 5.1's requirement that every seed ingredient links to a canonical item.

That is a fourth tool directory, against section 8's two. The alternative was
leaving the files unchecked until someone opened Xcode.

## Canonical item names are lowercase and singular, and aliases are a shared namespace

Names and aliases are validated as one namespace: no alias may repeat, and none
may equal another item's name. Section 5.3 matches an ingredient by exact name,
then alias, then fuzzy, so a string claimed by two items is ambiguous at exactly
the step every merge depends on.

The table has 297 items and 71 staples. Staples default to a pantry status of
`have`, which is what keeps salt, olive oil and black pepper off every list, the
first of Mealime's shortcomings listed in section 1a.

## The seed library ships 12 recipes, not 40 to 60

Section 5.1 asks for 40 to 60 and Phase 0b only asks for a loader that imports
the file. Twelve is enough to exercise the loader, the scaling, and the list
generator against real data, and the rest is Phase 1 content work.

It matters less than it looks for the owner: his 213 rescued Mealime recipes are
his library. The seed set is what a stranger sees on first launch, which is a
section 0 concern and belongs with the rest of the public release work.

## The NYT Recipe Box is collected through hidden frames, not by fetching HTML

Fetching `/recipe-box` and its folder pages returns an empty shell: on
2026-09-15 a crawl fetched 8 pages successfully and found zero recipes in every
one, while the same page open in a tab showed 48. The list is built client side.
`hasNextData: true` with zero recipes in the payload said the same thing.

So `collect()` loads each page in a hidden same origin iframe and lets the
page's own JavaScript render the list, then reads the frame's DOM. That keeps
the whole run to a single paste, rather than making the owner open eight lists
and re-paste the script on each.

`crawl()` is kept rather than deleted. It costs nothing, it is the right shape
for a server rendered site, and it now reports the client rendering diagnosis
instead of a silent zero.

## The deployment target is iOS 18, not the iOS 17 in the spec

Section 3 sets a floor of iOS 17, written when that was one version back. The
owner's Mac runs Xcode 27 against the iOS 27 SDK, so 17 is now several versions
back, and section 12 asked for the minimum to be confirmed rather than assumed.

iOS 17 is the expensive floor specifically because it is where SwiftData
shipped, at its roughest, and Mise puts every record in SwiftData from Phase 0b
onward. iOS 18 avoids that while still reaching phones back to 2018 hardware,
which keeps section 0's audience of Mealime users largely intact. Raising it
further would buy little and cut real people off.

Reversible until the models and views are written against it, which is why it
was settled before Phase 0b rather than during.

## The bundle identifier is com.benkleiman.mise and there is no team id yet

A bundle identifier is only a unique string, and Apple does not verify domain
ownership, so this needs no purchase or setup and can change until the first App
Store submission.

An Apple Developer team id is deliberately not being collected. It is needed for
signing on a real device and for TestFlight, which is Phase 5. Everything up to
then runs in the simulator. Asking the owner to buy a developer membership now
would spend money months before it is used.

## The browser collectors hold state in memory, with sessionStorage as a backup

A NYT run reported 163 recipes and downloaded 96. The two numbers came from
different places: collect() counted its in-memory state while rescue() re-read
sessionStorage, so a write that failed part way through produced an honest
looking count and a short file. Nothing warned loudly enough to notice.

Memory is now the source of truth and sessionStorage is only a backup, so the
run finishes intact even when storage fills. status() compares the two and says
when they disagree, and the dump records that storage failed.

The proximate cause was scan() storing each page's Next.js hydration payload,
capped at 2MB apiece, which nothing downstream ever read. That is no longer
stored at all.

The general lesson, and it cost two rounds: a count shown to the user has to be
read from the same place the deliverable is written from, or it is not a check.

## The Xcode project sits at the repository root, with tests beside it

`Mise.xcodeproj` is at the root and the app sources are in `Mise/`, which is what
section 8 draws. Test files cannot live inside `Mise/` because that folder is a
synchronized group belonging to the app target, so everything in it compiles into
the app. `Mise/Tests/` in section 8 would put XCTest code in the shipped binary.
They live in `MiseTests/` instead, which is the only part of section 8's tree
that moved.

## The project uses Xcode's synchronized file groups

Xcode 16 and later can point a target at a folder and take whatever is in it,
rather than listing every file with its own identifier. The project file then
barely changes, which matters here for two reasons: adding a Swift file in a
cloud session does not require editing a format that cannot be checked without
Xcode, and two sessions working on the same project stop colliding in the one
file they both have to touch.

The cost is that build phase membership is inferred from file type. If
`canonical_items.json` ever fails to reach the bundle, that inference is the
first place to look.

## Phase 0b was written without a compiler, and the project file was checked by parsing it

The cloud session has no Swift toolchain and `download.swift.org` is blocked by
the network policy, so nothing here has been compiled. That was the owner's call
rather than the plan in `PHASE-0B.md`, which was written for a Mac session.

What could be checked was checked. `project.pbxproj` is generated from a
description rather than typed, and then parsed with a NeXTSTEP plist reader that
resolves every object reference, looks for orphans, and asserts the bundle
identifier and deployment target. Both scripts are kept in
`tools/xcodeproj-lint/`, for the same reason `tools/resource-lint` exists: a
cloud session that edits that file has nothing else to check it with. Once Xcode
has written to the project, the generator stops being safe to run and the
validator is the only half still useful. The resource files still go through
`tools/resource-lint`. Everything else waits for Xcode.

## Seeded records get deterministic identifiers rather than random ones

Every record the app ships with derives its id from a stable key: an RFC 4122
version 5 UUID over a fixed namespace and a string such as
`canonicalItem:kosher salt`. `StableID` does this, and its test checks the
implementation against the published RFC vector rather than only against itself.

This is what makes the seed loader idempotent without a "have I seeded" flag,
which is the kind of thing that gets out of step with the store it describes.
"Is this already here" becomes a set membership test on ids that were computed
the same way last launch.

It pays off again in Phase 5. Two devices in one household that both seed before
they ever sync produce identical rows rather than 297 duplicates to reconcile.

## Ordered relationships carry an explicit position

SwiftData does not promise an order for a to-many relationship. Ingredients,
steps, planned meals and grocery items all have one that matters, so each
carries a `position` and is read back through an `ordered...` accessor. Cook
mode showing step 4 before step 2 is the failure this avoids, and it is the kind
that appears only after a store reload.

## Tags are strings on the recipe, not their own entity

Section 4 writes `tags: [Tag]` and section 5.1 says tags are flat, lowercase and
mostly automatic. A join table buys nothing while that is true, and it costs a
fetch on every recipe row in a library section 5.1 expects to hold a thousand
items. If renaming a tag everywhere ever becomes a feature, that is when the
entity earns its place.

## The seed installer lives in App, not in Domain/Services

`PHASE-0B.md` asks for `Domain/Services` to stay free of SwiftUI and SwiftData so
the grocery list math can move into a package later without untangling anything.
Seeding is split along that line: `SeedCatalog` decodes and cross checks the two
JSON files and imports only Foundation, and `SeedInstaller` writes models and
lives in `App/Seeding`.

Everything that can be got wrong about the seed, an unknown aisle, an ingredient
that resolves to nothing, a step pointing at an ingredient the recipe does not
list, is decided in the half that needs no store and no screen to test.

## The skeleton builds in Swift 5 language mode

`SWIFT_VERSION` is 5.0 and `SWIFT_STRICT_CONCURRENCY` is minimal. Swift 6 mode
against an Xcode 27 SDK would turn a skeleton with no concurrency in it into an
argument about actor isolation, and the code that will actually do concurrent
work, the importer, the AI proxy client and the sync engine, is not written yet.
Worth revisiting when it is.

## The Recipes and Pantry tabs show what was seeded rather than an empty state

Phase 0b asks for an empty state on every tab, and each tab has one. Two of them
are not reachable on a fresh install, because seeding puts 12 recipes and 71
pantry staples in the store before the user sees anything, and a screen reading
"No recipes yet" under twelve recipes would be a lie.

So those two tabs show a plain read only list when there is something in it: no
search, no filters, no detail screen, no editing. That is also the only way to
see from inside the app that the seed worked.

## The recipe step model is called RecipeStep

Section 4 names it `Step`. That is a common enough word to collide with
something in SwiftUI or Foundation later, and renaming a `@Model` class after it
has a store behind it is a migration. Done now, when it is free.
