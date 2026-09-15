# TODO

Known gaps, found while building. Section 11 asks for this list to be kept.

## Blocked on the owner

- [x] Mealime rescue ran on 2026-09-14 from the owner's signed-in Chrome. No
      token was needed. See DECISIONS.md.
- [ ] **Chrome bookmarks export** (`bookmarks.html`) of the open recipe tabs, to
      keep in `data/`. Section 12, Phase 0a. Once it is there, run
      `cd tools/bulk-import && npm run inventory` for the counts.
- [ ] **Run the NYT Recipe Box export.** `tools/nyt-export/` is written and
      tested but has never run against the real site. Start with
      `__nyt.probe()`, and if all three extraction strategies return zero, send
      that output back rather than guessing at the markup.
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
- [ ] Nothing announces the tool to Mealime users yet. A post in the places
      section 12 mentions (Reddit, the Mealime support community) would need to
      go up well before 2026-10-21 to be useful to anyone.

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
- [ ] **Parked at 96 of 163.** `data/nyt/nyt_recipe_box.json` holds 96 real
      recipes, all filed under one generic list with none marked cooked, so the
      folders and the Cooked list are missing. Four attempts to produce a
      complete dump did not, most likely because an older copy of the collector
      was pasted each time; the collector is now version stamped and convert
      warns when a dump is stale, which should settle it next time.

      Parked deliberately rather than abandoned: NYT is not shutting down, the
      recipes are safe in the Recipe Box, and this file is not consumed until
      Phase 4. Finishing it later costs nothing, because the app dedupes on the
      NYT numeric id per section 5.6a, so a later complete import adds the
      missing recipes without duplicating the 96 already there.

      To resume: paste `browser/collect.js`, confirm the banner shows the
      current version, then `__nyt.reset()`, `await __nyt.collect()`,
      `__nyt.status()`, `__nyt.rescue()`. Expect 163, folders Easy
      Kid-Friendly Recipes (70) and Recipes (44), and a cooked count above zero.
- [ ] If hidden frames turn out to be blocked, the next thing to try is the
      JSON endpoint the page itself calls to build the list. Capture it with
      `browser/capture-api-calls.js` from the mealime-export tool.
- [ ] `crawl()` fetches folder pages directly, which is faster than visiting
      them but can miss lazily loaded rows. Any folder whose count looks short
      needs `scan()` run on it in the browser instead.
- [ ] Nothing fetches the recipes themselves. That is Phase 4, by design: the
      app runs each URL through the JSON-LD pipeline, so the export only carries
      URLs, folders and the cooked flag.

## Bulk import

- [ ] The `looksLikeRecipe` heuristic is deliberately generous and has only been
      run against the test fixture. Check its calls against the real bookmarks
      file before trusting the "not recipes" count.
- [ ] `src/bookmarks.mjs` is the reference implementation for Phase 4's Swift
      port. Keep the fixture in step with whatever the app ends up handling.

## Environment

- [ ] No Swift toolchain or Xcode in the cloud environment, so no Swift code can
      be compiled or tested there. The app target has to be built on the Mac.
      A session start hook that installs the Swift Linux toolchain would let the
      platform independent domain services be tested in the cloud.

## Resources

- [x] `canonical_items.json`: 297 items across the 18 aisles, 71 staples,
      validated by `tools/resource-lint`.
- [ ] `seed_recipes.json` has 12 recipes. Section 5.1 asks for 40 to 60, so 28
      to 48 more in Phase 1. The owner's 213 rescued recipes cover his own
      library, so this set matters for strangers rather than for him.
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
- [ ] `Cmd + U` was never run, so the 26 unit tests have not been executed on a
      Mac. The app working is stronger evidence than the tests would be, but
      run them before Phase 1 builds on top of this.
- [ ] No app icon, and no loading state while seeding runs after first render.
