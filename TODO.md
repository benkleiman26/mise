# TODO

Known gaps, found while building. Section 11 asks for this list to be kept.

## Blocked on the owner

- [x] Mealime rescue ran on 2026-09-14 from the owner's signed-in Chrome. No
      token was needed. See DECISIONS.md.
- [ ] **Chrome bookmarks export** (`bookmarks.html`) of the open recipe tabs, to
      keep in `data/`. Section 12, Phase 0a. Once it is there, run
      `cd tools/bulk-import && npm run inventory` for the counts.
- [x] The NYT Recipe Box export ran on 2026-09-15: 169 recipes with folders and
      cooked flags. See the NYT export section below.
- [x] Bundle identifier settled as `com.benkleiman.mise`. No Apple Developer
      team id is needed until Phase 5, since everything before that runs in the
      simulator.
- [x] Minimum iOS version settled at 18.0, against the iOS 27 SDK. See
      DECISIONS.md. The spec's section 3 still says 17 and should be updated
      when the owner next edits it.
- [ ] No iOS 18 simulator runtime is installed, only 26.5. Building for an 18
      target and running on 26.5 is fine, but nothing is ever exercised on the
      floor. Install an iOS 18 runtime before the Phase 5 TestFlight build.

## Mealime export

Mealime shut down on 2026-10-21. The rescue completed on 2026-09-14, five weeks
ahead of it, and `data/mealime/` is the only copy of that data now. Everything
below about re-running or re-fetching is history rather than a possible action.

- [x] The guessed API routes were wrong because there is no API. The rescue now
      runs in the browser against the recipe CDN. See DECISIONS.md.
- [x] The rescue ran for real: 54 favourites from the CDN, 159 own recipes from
      the account object, 424 images. The CDN JSON shape matches section 1a.
      `_normalize_report.json` has 15 warnings, 13 of them recipes the owner
      had deleted in Mealime (kept, flagged `is_deleted`) and 3 own recipes
      with no instructions (Pinto bean patties, Crunchy Roll Bowls, Cucumber
      Sushi), which had none in Mealime either.
- [ ] Two own recipes have a Google ad click URL as `source_url` instead of the
      recipe page (Crisp Gnocchi With Brussels Sprouts and Brown Butter is
      one). Nothing to recover; the app importer should treat a
      googleadservices host as "no source".
- [ ] Cook history for published recipes that were never favourited is keyed
      `variant:<id>` because the account object does not carry their uuid.
      Their content was not rescued and cannot be now; the counts are kept.
- [ ] `rescue.js` and `collect-localstorage.js` are superseded by
      `rescue-state.js` and could be removed once nobody else needs them.
- [ ] The crawl follows one level deeper only from pages that held recipe ids.
      If a list page is paginated behind a link that holds none itself, that
      branch is missed. Check the page count it reports against the site.
- [x] Favorites, manual grocery items (14), collections (8), notes, ratings, and
      preferences all come straight from the account object now.
- [x] Recipe images are now downloaded by `npm run images`, so the rescue does
      not depend on Mealime's CDN outliving the service.
- [x] The `mise` repository is public, so the export tool is already runnable by
      any Mealime user. Section 9, Phase 0a.
- [ ] The tool was never announced to other Mealime users, and that window has
      closed: Mealime shut down on 2026-10-21 and the API it read is gone, so
      `tools/mealime-export` can no longer rescue anyone's data.

      What is still worth having is the other half, the app's "Import from
      Mealime" screen in section 5.7, which reads a `mealime-export.json` that
      someone saved before the shutdown. Anyone who ran any export still has a
      file. Keep that path; drop the idea of a timely rescue post.

## NYT export

- [x] Page structure confirmed on 2026-09-14: the DOM and raw link matching each
      found all 48 recipes on a page, the hydration payload found none. It
      paginates with `?page=N`, folders are numeric ids, and Recently Viewed is
      now excluded.
- [ ] The hydration strategy finds nothing on the Recipe Box. Harmless, since
      the DOM carries the list, but it means one of the three fallbacks is dead
      weight there. Leave it for recipe pages, which may hydrate differently.
- [x] Fetching page HTML finds nothing: the Recipe Box is rendered client side.
      `collect()` now renders each page in a hidden same origin frame.
- [x] collect() ran and found 163, matching the expected count.
- [x] **Done, 2026-09-15.** `data/nyt/nyt_recipe_box.json` holds 169 recipes,
      folders "Easy Kid-Friendly Recipes" (70, tag "kid friendly") and "Recipes"
      (44, no tag, too generic), and 2 marked cooked (Ben has only ever marked
      two recipes cooked in NYT, confirmed on the Cooked Recipes page). The raw
      dump is kept at `data/nyt/raw-nyt-recipe-box-2026-09-15.json`.

      Collected by driving the real tab through each list from the cloud session
      rather than the in-page hidden frames, which froze the renderer. The key
      fix was scoping the harvest to `[class*="cardGrid"]`: a folder page also
      renders a `carousel_cardList` of recommendations, and the old unscoped
      selector tagged those ~26 extra recipes as belonging to the folder. With
      grid scoping the folders came out at exactly 70 and 44. 169 is a touch
      over the 163 expected on 2026-09-14; the box grew, and the app dedupes on
      the NYT id anyway.
- [ ] Only 48 of 169 recipes carry a title in the dump, since later pages were
      swept for ids only. Harmless: the app refetches each URL and gets the
      title from JSON-LD. Re-run with titles if a nicer offline list is wanted.
- [x] `collect.js` now scopes its harvest to `[class*="cardGrid"]`, so a folder
      page's recommendation carousel no longer leaks into folder tags. Collector
      version 2026-09-15.3.
- [ ] The in-page hidden-frame walk in `collect.js` froze the renderer when run
      over CDP from a cloud session (many heavy iframes at once). The reliable
      path was navigating the real tab per list. If `collect.js` is ever run by
      hand it may still be fine, but a rewrite that navigates rather than frames
      would be sturdier.
- [ ] `crawl()` fetches folder pages directly, which is faster than visiting
      them but can miss lazily loaded rows. Any folder whose count looks short
      needs `scan()` run on it in the browser instead.
- [ ] Nothing fetches the recipes themselves. That is Phase 4, by design: the
      app runs each URL through the JSON-LD pipeline, so the export only carries
      URLs, folders and the cooked flag.

## Bulk import

- [ ] Run against Ben's real bookmarks export on 2026-09-15: 49 bookmarks in
      folders Finance, Riprova, Wellness, and zero actual recipes. It was his
      bookmarks bar, not the folder of open recipe tabs the import is meant for,
      so there was nothing to import. The recipe tabs were never bookmarked.
- [x] Fixed the `looksLikeRecipe` false positives. It now returns a tier
      (`recipeSignal`): nyt, foodHost, recipePath, recipeTitle, maybe, or no.
      Account-shaped paths (login, banking, credit-cards, billing and the rest)
      are ruled out outright unless the host is a known food site, and the
      inventory reports confident and maybe counts separately rather than one
      number that treats a bank login like a recipe. The eight account URL
      shapes from the real export are in the tests.
- [ ] **The bookmarks input was the wrong folder.** The export was the bookmarks
      bar, not a folder of the open recipe tabs. If those tabs are still open,
      bookmark them into one folder, export again, and run the inventory with
      `--folder`. If they are gone, so is that batch; nothing else depends on it.
- [ ] `src/bookmarks.mjs` is the reference implementation for Phase 4's Swift
      port. Keep the fixture in step with whatever the app ends up handling.

## Phase 1

The three domain services are done and verified. What remains in Phase 1 is all
user interface, so it belongs on the Mac: library browsing with collections,
tags, smart lists and facet chips, recipe detail with serving scaling, manual
entry, and the week plan. Section 5.1 and 5.2.


- [x] `UnitConverter` written, with `MiseTests/Fixtures/unit_conversion.json`
      stating its behaviour and `tools/resource-lint` verifying every expected
      value against the multiplier table.
- [ ] **The Swift has never been compiled.** No toolchain here. `UnitConverter`
      and `UnitConverterTests` need a build and a `Cmd + U` on the Mac. The
      fixtures are checked; the Swift transcription of them is not.
- [x] The fixture JSON reaches the test bundle. Confirmed by the tests running
      at all.
- [x] `IngredientParser` written, with a 52 case corpus in
      `MiseTests/Fixtures/ingredient_parsing.json`. `tools/resource-lint`
      checks every case is self consistent: units are real, quantities match
      what the line says, and each piece of expected output appears in the
      input, so no case can expect something that was never there.
- [x] The 379 line round trip passes, as do the 379 line resolution check and
      the corpus for each service.
- [x] `CanonicalMatcher` written, with 31 cases in
      `MiseTests/Fixtures/canonical_matching.json`. Every case is checked
      against the real canonical table: the item exists, the aisle is right,
      and the stated rung of the ladder is the one it actually matches on.
- [x] All 379 seed ingredient lines resolve to the item the seed data names,
      and none needs review. Enforced by `tools/resource-lint`, so it cannot
      break without a failure here.
- [x] **All three services verified on the Mac, 2026-11-01.** 61 tests pass,
      exit code 0, against Xcode 27 on the iPhone 18 Pro simulator. Getting
      there took two compile rounds and five real bugs, all recorded in the
      commit history.
- [ ] `Unit` shadows `Foundation.Unit`, so test files say `Mise.Unit`. Fine
      while it is only tests. If the Share Extension needs the same prefix in
      Phase 4, rename the enum instead of spreading it.
- [ ] The matcher has no edit distance rung, so a typo like "cilatro" resolves
      to nothing. Section 5.3 only asks for exact, alias and fuzzy, and
      containment covers fuzzy; add edit distance if real imports need it.
- [x] Learned aliases persist, in their own field that seeding never touches.
- [ ] Nothing undoes a categorisation. Choosing the wrong grocery item means
      editing the store by hand.
- [ ] A name can only be taught to an existing grocery item. There is no way
      to add a new one from that screen, which the long tail will want.
- [ ] Seed recipes have the same shape of problem as the canonical items did:
      an existing one is skipped rather than refreshed, so editing a built in
      recipe's text and shipping it does nothing for anyone who already has it.
      Lower stakes than the item table, but the same bug.
- [ ] No density override on canonical items yet, so cups to grams is always
      refused. Section 4 allows the override; nothing needs it before Phase 2.

## The first usable loop

Landed on 2026-11-01. It compiles against the iOS 27 SDK and the suite is
green on the Mac: 70 tests, no failures, up from 61 before `ListGenerator`.

- [x] `xcodebuild build` and `xcodebuild test` both exit 0 with the new stores
      and views in the target. First try, no errors.
- [ ] Compiling is not running. Nobody has used the loop against a real plan
      yet, so the list has never been read by a person who then went shopping.
- [ ] No tests cover the two new stores. They need an in-memory container and a
      seeded household, which is what `SeedInstallerTests` already sets up.
- [x] `GroceryItem` now stores the real quantity list rather than one quantity
      and a `note` holding the written form. The `note` field is free for an
      actual note.
- [x] **Mealime import.** `tools/mealime-import` converts the rescued library,
      and Settings imports the result. The converter ran against the real
      library on 2026-11-02: 213 read, 213 converted, nothing skipped, 2436
      ingredient lines. 159 have no cooking time and 3 have no steps.
- [x] **NYT import** is built: `tools/nyt-export/browser/fetch-recipes.js`
      fetches the pages in the owner's browser, `tools/nyt-import` reshapes
      what it downloads. 10 tests. Not yet run against the real 169.
- [x] Imported Mealime recipes carry their rescued photo, copied next to the
      import file and stored on the recipe. Written 2026-11-02, not yet run
      against the real 424.
- [x] NYT recipes carry their photo, downloaded during conversion from the
      public image CDN the recipe page itself loads them from.
- [ ] Photos go into the store at whatever size Mealime served, under
      `.externalStorage`. If the database gets uncomfortable, downscaling to
      something like 800px on the long edge during conversion is the fix.
- [x] An imported recipe with no cooking time no longer shows "0 min". 159 of
      the owner's 213 have none, because Mealime leaves it null on a recipe you
      typed in yourself. The library and plan rows leave the time out and the
      detail screen says it was not recorded.
- [x] A recipe's serving count is correctable, and the recipe screen scales to
      however many are eating.
- [ ] Nothing else about a recipe can be edited: no fixing a missing cooking
      time, a wrong title, or an ingredient the parser read badly. Manual entry
      and full editing are the rest of Phase 1.
- [ ] Scaling does not touch the method, so step 3 still says "add two cups"
      when the ingredient list says four. The footer admits it. Rewriting
      numbers inside prose is its own problem and probably wants the amounts
      marked up at import rather than found by regex later.
- [x] The user can categorise an unmatched ingredient, and it applies to every
      recipe already waiting on that name. Section 5.3 rule 2.
- [x] Web page furniture the Mealime "import from a link" captured is dropped
      by the converter, and the run reports how many lines went.
- [x] Deleting a recipe was not taking its ingredients with it. Children are
      deleted explicitly now, and each import sweeps anything already stranded
      and reports the count. A non-zero sweep after a clean run means it leaked
      again.
- [x] Checked on 2026-11-02: the plan and grocery paths already delete their
      children explicitly, so the import was the only place relying on the
      cascade rule. Nothing else in the app deletes a parent record.
- [ ] "Salt and pepper" is one line asking for two things, and there are 11 of
      them. Splitting on "and" is only safe for a short list of known pairs.
- [ ] The import's match rate should be measurable without a simulator. A
      command in `tools/resource-lint` that runs the table over an import file
      would make the next pass a loop rather than a round trip.
- [x] Press and hold a grocery row to see which meals need it.
- [ ] Making a list with no meals planned still creates an empty `GroceryList`
      record. It shows as the empty state, so it is invisible, but it is junk.
- [ ] The pantry cannot be edited from the grocery list, so "we already have
      this" means leaving the shop screen to go and say so.
- [ ] The pantry seeding rule changed after the first real list. An install
      from before 2026-11-01 keeps its old all `have` entries, because seeding
      is idempotent. Delete the app and run again to pick up the new defaults.
- [x] The pantry is editable: have, low, out, or not tracked, with the search
      reaching the whole grocery table so anything can be found and tracked.
- [x] Facet chips, collections, sort orders and favouriting, with the search
      reaching titles, summaries, tags and ingredients. Written 2026-11-02.
- [x] Paste a link, reading the recipe the site publishes rather than scraping
      the page.
- [ ] Still to come in Phase 1: writing a recipe down by hand, editing an
      imported one beyond its serving count, and smart lists that save a set
      of filters under a name.
- [x] A link import downloads the photo, checks it is actually an image,
      caps it at five megabytes and shrinks it to 1200px before storing.
- [ ] The Mealime and NYT file imports do not shrink their photos, so those
      go into the store at whatever size they came at. The same helper would
      do it; it lives in the link import for now.
- [ ] A site that renders its recipe client side, or hides it behind a sign
      in, cannot be read. That is most newspaper sites. There is no fallback
      and deliberately so, but the error should probably suggest the Share
      Extension once Phase 4 builds one.
- [ ] Dish types cannot be corrected by hand. When the classifier gets one
      wrong the only fix is a rule change and a relaunch. Editing a recipe
      should let the cook set them, and that edit has to survive the backfill,
      which currently skips anything that already has one.
- [ ] The classifier never runs again on a recipe that already has a type, so
      improving a rule does not reach the existing library. A "reclassify
      everything" action in Settings would, and would be two lines.
- [ ] Nothing marks a meal as cooked, so "Cooked" only ever shows what the NYT
      import brought in. Cook mode is Phase 3 and owns that.

## Environment

- [ ] No Swift toolchain or Xcode in the cloud environment, so no Swift code can
      be compiled or tested there. The app target has to be built on the Mac.
      A session start hook that installs the Swift Linux toolchain would let the
      platform independent domain services be tested in the cloud.

## Resources

- [x] `canonical_items.json`: 297 items across the 18 aisles, 71 staples,
      validated by `tools/resource-lint`.
- [x] `seed_recipes.json` holds 45 recipes, within the 40 to 60 section 5.1
      asks for. Validated by `tools/resource-lint`.
- [ ] No recipe images for the seed set. The app needs a sensible placeholder,
      or the recipe cards look broken on first launch.
- [ ] Aisle order in `canonical_items.json` is the spec's default, not the
      owner's store. Section 12 asks him for his usual store's order in Phase 2.

## Phase 0b

Done and verified on 2026-09-15. It builds in Xcode 27, runs in the iPhone 18
Pro simulator on iOS 27, and Settings reports 45 recipes, 297 grocery items and
71 pantry entries. The same three numbers came back on a second launch, so
seeding is idempotent on disk and not only in the in-memory tests.

- [x] The ambiguous `id` that the pre-build review predicted did not happen.
      The generic over `PersistentModel` and `HouseholdRecord` compiles.
- [x] The two JSON resources reached the app bundle, which was the assumption
      most likely to be silently wrong.
- [x] The full suite now runs on the Mac, 61 tests, all passing.
- [ ] No app icon, and no loading state while seeding runs after first render.
