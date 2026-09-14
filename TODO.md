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

- [ ] The script has never run against the real API. Endpoint and auth scheme
      guesses in `src/discover.mjs` are unverified. Run `npm run discover`
      first and expect to adjust the candidate lists.
- [ ] Preferences mapping in `normalizePreferences` is written against the
      preference names in section 1a, not against a real response.
- [ ] Recipe images are referenced by URL, not downloaded. If Mealime's image
      CDN goes down with the rest of the service, the URLs die too. Worth adding
      an image download pass before the deadline.
- [ ] Publish `tools/mealime-export/` to a public repository with the README as
      written. Section 9, Phase 0a, asks for this so other Mealime users can run
      it. The `mise` repository itself is private.

## Environment

- [ ] No Swift toolchain or Xcode in the cloud environment, so no Swift code can
      be compiled or tested there. The app target has to be built on the Mac.
      A session start hook that installs the Swift Linux toolchain would let the
      platform independent domain services be tested in the cloud.

## Not started

Everything from Phase 0b onward. See section 9 of the spec.
