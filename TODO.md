# TODO

Known gaps, found while building. Section 11 asks for this list to be kept.

## Blocked on the owner

- [ ] **Mealime auth token** so the export can actually run. Section 12, Phase
      0a. This has a hard deadline of 2026-10-21. See
      `tools/mealime-export/README.md` for how to copy it.
- [ ] **Chrome bookmarks export** (`bookmarks.html`) of the open recipe tabs, to
      keep in `data/`. Section 12, Phase 0a.
- [ ] Bundle identifier and Apple Developer team ID. Section 12, Phase 0b.
- [ ] Confirm iOS 17 as the minimum. Section 12, Phase 0b.

## Mealime export

- [ ] **The guessed routes are wrong.** A first run on 2026-09-14 returned 404
      for all six identity candidates under all five auth schemes, so neither
      `api.mealime.com/api/v2` nor those paths are right. `mealime.com` is not
      reachable from the cloud build environment, so the real routes have to
      come from a browser: run `browser/capture-api-calls.js` on my.mealime.com
      and correct `IDENTITY_CANDIDATES` and `COLLECTION_CANDIDATES`.
- [ ] Preferences mapping in `normalizePreferences` is written against the
      preference names in section 1a, not against a real response.
- [x] Recipe images are now downloaded by `npm run images`, so the rescue does
      not depend on Mealime's CDN outliving the service.
- [x] The `mise` repository is public, so the export tool is already runnable by
      any Mealime user. Section 9, Phase 0a.
- [ ] Nothing announces the tool to Mealime users yet. A post in the places
      section 12 mentions (Reddit, the Mealime support community) would need to
      go up well before 2026-10-21 to be useful to anyone.

## Environment

- [ ] No Swift toolchain or Xcode in the cloud environment, so no Swift code can
      be compiled or tested there. The app target has to be built on the Mac.
      A session start hook that installs the Swift Linux toolchain would let the
      platform independent domain services be tested in the cloud.

## Not started

Everything from Phase 0b onward. See section 9 of the spec.
