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

Not started. `PHASE-0B.md` is the handoff for a Mac session, since the cloud
environment cannot compile Swift. Everything in that phase that does not need a
compiler is done: both resource files and their validator.
