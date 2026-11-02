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

## Expected behaviour for the domain services is written as fixtures, not only as tests

There is no Swift toolchain in the cloud environment and no route to one:
`download.swift.org` is denied by the network policy, `gh` is scoped to attached
repositories, and there is no apt package. So Swift written here cannot be
compiled, let alone tested, before it reaches a Mac.

`MiseTests/Fixtures/unit_conversion.json` is the answer. It states what
UnitConverter should do as data: the multiplier table, every conversion and its
result, the combinations and how they render, the fractions. Every expected
value in it is recomputed from its own multiplier table by
`tools/resource-lint`, which is plain Node and runs here. So the behaviour is
verified before any Swift exists, and a failing Swift test means the code
disagrees with a checked expectation rather than two unverified things
disagreeing with each other.

The validator mirrors the merge and format rules in about forty lines of
JavaScript. That is duplication, and it is the one kind worth having: it checks
the test data rather than the app, and if it ever drifts from the Swift the
Swift tests fail rather than the fixture quietly being wrong. It is a different
case from the Mealime exporter, where a second ingredient parser was refused
because both would have been production code.

## Converting stays inside a family, and a merge never loses quantity

Section 4 allows conversion only within volume or within mass, with cups to
grams refused unless the canonical item carries a density override. The override
is not built yet; nothing needs it until Phase 2.

Discrete units go further: a can only ever adds to another can. Two cans and one
bunch stay two lines, because a can is not some number of bunches and guessing
is worse than two lines.

A merged quantity is expressed in the largest unit present that still leaves at
least one of it, so half a pound plus four ounces reads "12 oz" rather than
"0.75 lb". Quantities are rendered with the fractions a measuring cup actually
has, and anything that is not one of those is shown as a decimal rather than
rounded to a fraction that would be a small lie.

Section 4's own example, "1 cup + 2 tbsp", is read as showing the join format
for two quantities that cannot be added, since those two particular quantities
are both volume and therefore do add, to 1 1/8 cups. The format is used where
the rule actually bites: a volume beside a mass, or two different discrete units.

## The parser reports confidence, because a confident wrong answer is the worst outcome

Section 5.1 shows every parsed line for confirmation and section 1a asks us to
query only the lines we are unsure about. Those only work if the parser knows
when it is guessing, so `confidence` is part of what it returns rather than
something a caller infers.

It only ever falls. A line with a range, a leading participle and two
ingredients on it lands on the worst of those doubts, not the last one checked.

Three things drop it to `low`: a number still sitting in the name, which means
the split went wrong; the word "and" in the name, which usually means two
ingredients on one line; and a vague measure such as "a handful". Each is a case
where producing something plausible would be worse than admitting the problem.

## A range takes its lower bound

"1 to 2 cloves garlic" is read as one clove. Buying too little is recoverable at
the stove and buying too much is waste, and section 2 puts the shopper first.
Confidence drops to medium so the line is reviewable.

## A participle leading the name is preparation, unless the unit is a container

"1/2 cup chopped parsley" is parsley you chop, so "chopped" is preparation. "1
can diced tomatoes" is a tin of diced tomatoes, a thing you buy, so the name
stays whole. The rule is the unit: can, package and bunch keep their participle.

Words that also name a product are kept out of the verb list entirely.
"Toasted" is the clearest case, since toasted sesame oil and toasted sesame
seeds are both things on a shelf, and stripping it would send the shopper after
the wrong item.

## Section 4's sixteen units are the only units

A "head" of garlic or a "sprig" of thyme stays in the name rather than becoming
an invented unit, and confidence drops to medium to record that a real amount
was not captured. Inventing units would quietly break every merge that depends
on them being a closed set, which is most of section 5.3.

## Fuzzy matching requires the head noun to agree

Section 5.3's third rung is a fuzzy match. The rule is containment: every word
of the canonical item's name appears in the ingredient, and both end on the same
word.

The second half is the whole guard. Containment alone resolves "milk chocolate"
to milk, because the word is right there, and the shopper comes home with the
wrong thing. English food names put the thing itself last, so comparing the
final word separates "coconut milk", which is milk, from "milk chocolate", which
is not. There is a test named after that case.

Where several items are contained, the most specific wins, so "coconut milk"
beats "milk" rather than racing it.

A containment hit is medium confidence and gets reviewed. An exact name, an
alias, or something the user taught us goes through silently. That split is what
section 1a asks for: confirm only the lines we are unsure about.

## Teaching returns a new matcher rather than mutating one

Section 5.3 says an unmatched ingredient is categorised once by the user and
that teaches the alias table. `teaching(_:as:)` returns a matcher that knows the
new phrase, leaving the original alone, so a list generation already in flight
cannot have the rules change underneath it.

## The seed library's resolution is a lint rule, not just a test

Section 5.1 requires every seed recipe to carry canonical item links so the list
generator works on first launch. `tools/resource-lint` now resolves all 379 seed
ingredient lines against the real table and fails if any one of them stops
resolving to the item the seed data names.

That runs without Xcode, so editing either JSON file cannot quietly break the
thing section 2 calls the hero feature. All 379 currently resolve, and none of
them needs review.

## Our measurement type is called Quantity, because Foundation owns Measurement

The first compile of the Phase 1 services failed on two name collisions, both
with Foundation. `Measurement` is a core Foundation type, and shadowing it made
every test file that imports XCTest ambiguous. It was renamed to `Quantity`.

That one was straightforwardly a mistake on our side, and cheap to fix because
the type was a day old.

`Unit` is the other collision, and it stays. Section 4 calls them units, the
enum has been there since Phase 0b, and inside the module our `Unit` shadows
Foundation's cleanly. It is only ambiguous across `@testable import`, where both
are visible, so the three test files say `Mise.Unit`.

If that qualification starts appearing outside tests, for example in the Share
Extension in Phase 4, rename the enum then rather than spreading the prefix.

## The first usable version is the loop, not Phase 1's full library screen

The engine was finished before any screen used it: the four domain services were
written and tested, and the app still showed three empty states. Phase 1 as
section 5.1 describes it is a large screen, with collections, tags, facet chips,
sort orders and manual entry.

The loop the owner asked for is smaller than that: choose recipes, see them as a
week, get one grocery list. So the loop was built first and the rest of Phase 1
left for later. What landed is search, a recipe detail screen with one button,
a week list with per meal servings, and the list itself, grouped by aisle and
tappable.

The ordering matters because everything after this is easier to judge once the
app can be used end to end. A missing facet chip is visible and can wait; a
list generator that merges the wrong rows is not visible at all until a real
plan runs through it.

## The tab selection lives in RootView, so "Make the list" can land on the list

The grocery list is a different tab from the plan that produces it. Making the
list and leaving the user on the plan screen would mean the one action the app
exists for appears to do nothing.

`RootView` owns the selected tab and hands the Plan screen two closures, one to
reach the recipes and one to show the list. The alternative, a shared navigation
store in the environment, is more machinery than two closures for a decision
that only ever moves between four fixed tabs.

Adding a recipe deliberately does not change tabs, because people add several in
a row. It shows a short confirmation instead.

## Deleting a child record needs a repository method, not a context

Dropping a `PlannedMeal` out of `plan.entries`, or a `GroceryItem` out of
`list.items`, only breaks the link. The record stays in the store with a nil
parent, invisible to every screen and permanent. A cascade delete rule only
fires when the parent itself is deleted.

Section 3's rule is that nothing outside `Domain/Repositories` touches a
`ModelContext`, so the stores cannot delete a child themselves. Rather than
break that rule, `MealPlanRepository` gained `deleteEntry` and
`GroceryListRepository` gained `deleteItem`.

This is the first case of a repository needing a method about a child rather
than its aggregate root. If more of them appear, the right shape is probably a
single `delete(_:)` that takes any `PersistentModel`, but one method each is
honest about what is actually needed today.

## A grocery row with two quantities keeps its written form in `note`

`ListGenerator` can emit a row with two quantities, when a recipe asks for a
bunch of parsley and another asks for a quarter cup of it and the two cannot be
added. `GroceryItem` holds one `quantity` and one `unit`.

Rather than widen the model mid build, the first quantity goes in the two
fields and the full written form, "1 bunch + 1/4 cup", goes in `note`, which the
list screen prefers when it is set. The shopper sees the whole thing.

The model should grow a proper quantity list when something else needs it, and
TODO.md says so.

## A perishable staple starts at "low", not "have"

The first real list, three dinners on 2026-11-01, came out at ten rows. It was
correct, and it was missing eggs.

Every one of the 71 staples was seeded into the pantry as `have`, and section 4
says the generator excludes `have`. That is exactly right for kosher salt,
olive oil and cumin, which is what the rule was written for. It is wrong for
eggs, milk, butter, parmesan, frozen peas, garlic, scallions and yellow onion,
which are staples in the sense that every kitchen has them and also the things a
household rebuys every week.

The two failures are not symmetrical. An item wrongly on the list costs one tap.
An item wrongly off it means standing in the kitchen on Wednesday without eggs.
So the rule now leans the other way for anything perishable: a staple in
produce, meat, seafood, deli, dairy, bakery or frozen starts at `low`, which
section 4 includes, and everything else starts at `have`.

Classifying by aisle rather than by a new flag on each item means the table
cannot drift out of step with the rule, and adding a staple to the table gets
the right default for free.

This only applies on a first seed. Seeding is idempotent by design, so an
install that already has 71 `have` entries keeps them. Deleting the app and
running again is the way to pick the new defaults up.

## A hand added item joins the row it names, and remembers which part is yours

Asked for on 2026-11-01, after the first real list showed "lemon 1" from a
recipe and "lemons 2" typed by hand as two rows.

Merging them naively would be wrong in a way that only shows up on the second
regeneration. If the merged row stores one total and is then carried over as a
manual item, the next run adds the hand typed part to the recipe part again,
and the amount grows every time the list is made.

So `GroceryDraftItem` and `GroceryItem` both carry `manualQuantities`
alongside `quantities`: the total the shopper reads, and the part of it the
user typed. Regenerating rebuilds the recipe part from the plan and folds the
hand added part back in exactly once.

Folding happens before the check state comparison, so a merged row that has not
changed keeps its tick rather than losing it on every regeneration.

A hand added item that matches nothing on the list, like dish soap, still
becomes its own row, which is what section 5.3 asks for.

This replaced the `note` stopgap: `GroceryItem` now stores the real quantity
list, so a row with two quantities that cannot be added is stored as two
quantities rather than as one quantity and a sentence.

## Search matches the words typed, not the phrase

Searching "lemon past" returned nothing while "Lemon Garlic Butter Pasta" was
sitting in the list, because the filter asked whether the title contained that
run of characters, and no title does.

Every word typed now has to appear somewhere in the recipe's title, summary,
tags or ingredient names, in any order and as a prefix of a longer word. People
type the words they remember rather than the title, and they stop typing
halfway through a word.

## The scrolling bug was not a bug

Reported on 2026-11-01: no list in the app would scroll, on any screen. Two
changes went in chasing it, and both diagnoses were wrong.

The cause was the advice given for driving the simulator: click, hold, then
drag. Pausing before moving makes iOS read a long press rather than a scroll,
so the list does not move. Clicking and dragging in one motion, which is what
the user was already doing on the home screen, works.

Both changes stayed, because each is defensible on its own: `Tab` values are
the spelling iOS 18 introduced, and a checklist row reads better as a tap
target than as a button. Neither fixed anything, and the comments in those
files now say so. A comment that claims to fix a bug that never existed is
worse than no comment, because the next person preserves the shape for a
reason that was never true.

The lesson worth keeping is about evidence. Three rounds were spent on code
before anyone checked whether a system app scrolled, which would have settled
it in ten seconds. Rule out the harness before rewriting the thing under test.

## The importer reshapes in Node and parses in Swift

The Mealime library arrives as ingredient lines written the way people write
them: "2 scallions, trimmed then sliced crosswise 1/4-inch-thick", with the
quantity field empty because the owner typed most of these in himself.

The obvious place to parse that is the Node converter, where the files are. It
is the wrong place. `IngredientParser` already does exactly this job in Swift,
with 52 fixture cases, and `CanonicalMatcher` behind it with 32 more. A second
parser in JavaScript would be a second set of answers to the same question, and
the two would disagree within a week, in a way that only shows up as a
duplicated row on a grocery list months later.

So the split is: Node reshapes Mealime's fields into Mise's import shape and
keeps every ingredient line exactly as written. Swift parses, matches and
stores. An imported recipe then behaves on the grocery list identically to a
built in one, because it went through the same two pieces of code.

The import file is picked with `fileImporter` rather than read from a path
baked into the app. That is one more tap, and it is the version that works on
the owner's phone later rather than only in the simulator.

## Imported recipe ids are derived, so importing twice replaces

Keyed on `import:<source>:<external id>`, run through the same v5 UUID scheme
as the seed. Importing the same file again replaces those recipes rather than
building a second library, which matters because the first import will not be
the last: the converter will improve, and the owner should be able to re-run it
without cleaning up by hand.

The source is part of the key, so a Mealime recipe and an NYT recipe that
happen to share an id stay separate, and neither can collide with a seed recipe
even if it names one.

The replace is a delete and an insert, committed in that order. Doing both
inside one transaction asks a unique constraint to hold two rows with the same
id at once.

## Mise's Documents folder is visible in Files

Dragging a file onto the simulator window is the documented way to get one in,
and on 2026-11-02 it silently did nothing. Rather than hunt for why, the app
now sets `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace`, so its
Documents folder appears in the Files app under "On My iPhone".

That makes a file reachable by copying it into the app container, which on a
simulator is one shell command, and on a real phone means dropping a file into
Mise's folder from a Mac over Finder, or saving one there from Mail or
Messages. It is also the thing that makes an export worth having later: a
folder the user can see is a folder they can get a backup out of.

The alternative, reading a path baked into the app, would have worked today in
the simulator and nowhere else.

## The real library found four bugs the seed data never could

Importing the owner's 213 rescued Mealime recipes produced 2436 ingredient
lines, of which 344 matched no grocery item. The list of those 344 was worth
more than the count, because they were not all the same kind of failure.

**The parser was dropping names.** "2 garlic cloves" reads the unit off the end
of the phrase and left no name at all, so the whole raw line got stored as the
ingredient. Thirty five lines were garlic written that way. The seed library
writes "2 cloves garlic", so no fixture had ever covered the other order.

**The comma rule was eating ingredients.** "6 boneless, skinless chicken
thighs" split at the first comma and recorded the ingredient as "boneless".
The chicken was thrown away. The rule now asks whether anything before the
comma could be an ingredient at all once the quantity, unit and adjectives are
removed, and leaves the line alone when the answer is no.

**Measures with no unit were staying in the name.** "3 thyme sprigs" reached
the list as "thyme sprigs", which never merges with the thyme another recipe
asks for. The word is now dropped and confidence lowered, because losing the
measure is better than losing the merge.

**"X or Y" is one thing to buy.** "safflower or canola oil" is one bottle. The
first option is the one the writer led with.

The table grew from 297 items to 389 with 105 new aliases. That is the least
interesting of the four and was the only one visible from the count alone.

The lesson is that 45 seed recipes written in one house style cannot find
parser bugs. 213 recipes from dozens of authors found four in an afternoon.
Any future importer should expect the same, and the first import of a new
source is worth reading line by line rather than trusting the totals.

## A choice between ingredients is read by the matcher, not the parser

The first attempt cut "safflower or canola oil" at the "or" and kept the first
half. It turned "chicken or vegetable broth" into "chicken" and cost about
forty five lines their noun, which was worse than the problem it fixed.

The noun can belong to either half. "chicken or vegetable broth" keeps it at
the end, "Parmesan or Pecorino Romano" at the front, and "safflower or canola
oil" shares it. No rule decides that from the text alone, because the answer
depends on which readings are real products.

So the parser leaves the name whole and `CanonicalMatcher` offers every
reading to the table: the first half carrying the trailing words back, the
first half alone, the second half, and so on down a chain of "or"s. Whichever
resolves wins, at medium confidence because a choice was made on the cook's
behalf.

The general shape is worth keeping: when a decision needs a fact the parser
does not have, the parser should preserve the ambiguity rather than guess, and
the component that holds the fact should resolve it.

## The descriptor list is duplicated on purpose, and checked

`CanonicalMatcher.descriptors` grew from 20 words to 95 off the back of the
real import. The linter has its own copy because it validates the fixtures
without a Swift toolchain, which the cloud environment does not have.

Duplication that nothing checks is how two implementations quietly disagree,
which is the exact failure the import pipeline was designed to avoid. So
`npm test` in `tools/resource-lint` now reads the word list out of the Swift
file and fails if the two have drifted.

## A cascade delete rule was not enough, and the evidence was a count that would not move

Three imports of the same library reported 344, then 218, then 128 unmatched
ingredient names. The top of all three lists was identical: "red pepper" 14,
"garbanzo beans (chickpeas)" 14, "crumbled feta cheese" 10. Aliases for every
one of those had been added after the first run.

A count that does not move when the thing it counts has been fixed is not a
count of what you think it is. Those rows were never reparsed because they
were no longer attached to anything: the import deleted each recipe and
`@Relationship(deleteRule: .cascade)` did not take the ingredients with it.
Around two thousand rows, invisible to every screen, counted by every query,
growing by that much again on each import.

Two changes. Children are now deleted explicitly before their recipe, rather
than trusting the rule. And each import sweeps up anything already stranded
and reports how many, so the same leak cannot hide again: a non-zero "stale
rows cleared" after the first run means something is still leaking.

The diagnostic lesson is the one worth keeping. The unmatched count was
measuring two different populations added together, live rows and dead ones,
and no amount of work on the matching would ever have moved the dead half. The
tell was available from the first comparison: a number that stays exactly the
same across a change that should have moved it is evidence about the
measurement, not about the thing measured.

## Seeding refreshes an item that is already there, instead of skipping it

Three rounds of alias work moved the unmatched count from 344 to 218 to 128 to
123. The last round added 126 aliases and moved it by five.

The reason was one line in `SeedInstaller`: `if existing.contains(id) { continue }`.
Seeding was written to be idempotent, and it was, in the strongest possible
sense: an item already in the store was never touched again. Every alias added
to an existing item after first launch went into the resource file and never
into the store. `CanonicalMatcher` is built from the store.

Only brand new items ever took effect, which is why each round moved the number
a little and never as much as it should have. The signal was there from the
second round and I read it as a matching problem three times.

Seeding now refreshes an existing item's aliases, aisle, staple flag and
default unit when they differ from the resource file, and reports how many it
touched. The report is on the Settings screen, so a launch that quietly rewrote
part of the table says so.

The table is going to keep growing every time an import finds a gap in it, so
the refresh is worth more than the saving. A second launch with nothing changed
still writes nothing, which a test holds to.

This makes the resource file authoritative over the store for these four
fields. That is right today because nothing in the app edits a grocery item.
When section 5.3's "categorise this once and it learns" lands, what the user
teaches has to live somewhere the seed will not overwrite, and that is a
separate field rather than a merge into this one: a merge cannot tell a
deliberate removal from a user's addition.

## The app learns an ingredient name, so the list stops coming back to me

Four rounds of editing the resource file by hand took the owner's unmatched
ingredient count from 344 to 52. Each round was the same shape: he ran a query,
sent a list, I added aliases, he reimported. That loop does not end, because
every new recipe from a new author brings new phrasings, and most of what is
left is genuinely odd enough that only the cook knows what it meant.

Section 5.3 rule 2 always asked for this: flag what did not match, let the user
say what it is once, and remember. It is built now. Settings has a
"Categorise ingredients" screen listing every unmatched name, most used first,
with the recipes it came from so the cook can tell what it was. Tapping one
offers the grocery items, and choosing one applies it to every recipe already
waiting on that name rather than only to the next import.

What the user teaches goes in `learnedAliases`, a separate field from the
shipped `aliases`, because seeding overwrites the shipped ones whenever the
resource file changes. A merge into one field would not survive that, and
could not tell an alias deliberately removed from one a person added.

The resource file still matters: a name worth shipping to everyone belongs
there. But the file is now the floor rather than the only way up.
