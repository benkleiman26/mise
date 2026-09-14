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
- [ ] Bundle identifier and Apple Developer team ID. Section 12, Phase 0b.
- [ ] Confirm iOS 17 as the minimum. Section 12, Phase 0b.

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

- [ ] The Recipe Box page structure is assumed, not observed. The three
      extraction strategies are tested against stubbed markup only.
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

## Not started

Everything from Phase 0b onward. See section 9 of the spec.
