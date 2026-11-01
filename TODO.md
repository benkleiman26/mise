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

- [x] `UnitConverter` written, with `MiseTests/Fixtures/unit_conversion.json`
      stating its behaviour and `tools/resource-lint` verifying every expected
      value against the multiplier table.
- [ ] **The Swift has never been compiled.** No toolchain here. `UnitConverter`
      and `UnitConverterTests` need a build and a `Cmd + U` on the Mac. The
      fixtures are checked; the Swift transcription of them is not.
- [ ] Confirm `MiseTests/Fixtures/*.json` lands in the test target's resources.
      Same assumption that was worth checking for the app's own JSON, and
      `UnitConverterTests` fails with a clear message if it did not.
- [x] `IngredientParser` written, with a 52 case corpus in
      `MiseTests/Fixtures/ingredient_parsing.json`. `tools/resource-lint`
      checks every case is self consistent: units are real, quantities match
      what the line says, and each piece of expected output appears in the
      input, so no case can expect something that was never there.
- [ ] The Swift tests also round trip all 379 seed ingredient lines, which has
      never been executed. Two known divergences are expected and asserted:
      "shredded cheddar" comes back as cheddar with preparation "shredded", and
      a `count` unit comes back as no unit, which is the same thing.
- [x] `CanonicalMatcher` written, with 31 cases in
      `MiseTests/Fixtures/canonical_matching.json`. Every case is checked
      against the real canonical table: the item exists, the aisle is right,
      and the stated rung of the ladder is the one it actually matches on.
- [x] All 379 seed ingredient lines resolve to the item the seed data names,
      and none needs review. Enforced by `tools/resource-lint`, so it cannot
      break without a failure here.
- [ ] All three services are written. The first compile found two Foundation
      name collisions, now fixed, and nothing has been run yet.
- [ ] `Unit` shadows `Foundation.Unit`, so test files say `Mise.Unit`. Fine
      while it is only tests. If the Share Extension needs the same prefix in
      Phase 4, rename the enum instead of spreading it.
- [ ] The matcher has no edit distance rung, so a typo like "cilatro" resolves
      to nothing. Section 5.3 only asks for exact, alias and fuzzy, and
      containment covers fuzzy; add edit distance if real imports need it.
- [ ] Learned aliases live only in the matcher instance. Persisting them is
      Phase 2, when the user actually categorises something.
- [ ] No density override on canonical items yet, so cups to grams is always
      refused. Section 4 allows the override; nothing needs it before Phase 2.

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
- [ ] `Cmd + U` was never run, so the 26 unit tests have not been executed on a
      Mac. The app working is stronger evidence than the tests would be, but
      run them before Phase 1 builds on top of this.
- [ ] No app icon, and no loading state while seeding runs after first render.
