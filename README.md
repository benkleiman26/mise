# Mise

A personal meal planning and grocery list app for iOS, built to replace Mealime.

The loop: pick a handful of dinners for the week, turn them into one consolidated
grocery list grouped by store section with the pantry subtracted, then cook each
meal from a step by step cook view.

Full requirements live in the build spec, linked from `SPEC.md`. Decisions made while building are in
`DECISIONS.md`. Known gaps are in `TODO.md`.

## Layout

| Path | What it is |
| --- | --- |
| `Mise.xcodeproj` | The Xcode project. iOS 18 minimum, SwiftUI, SwiftData locally, Supabase backend later. |
| `Mise/App` | Entry point, dependency container, root tab bar, the first launch seed. |
| `Mise/Features` | One folder per feature: Plan, GroceryList, Recipes, Pantry, CookMode, Settings. |
| `Mise/Domain/Models` | SwiftData `@Model` classes and the enums from section 4. |
| `Mise/Domain/Services` | Pure logic. Seed decoding now, list generation and parsing later. No SwiftUI or SwiftData. |
| `Mise/Domain/Repositories` | Protocols plus SwiftData implementations. |
| `Mise/Resources` | `seed_recipes.json`, `canonical_items.json`, the asset catalog, AI prompts later. |
| `MiseTests` | XCTest target. |
| `tools/mealime-export` | One time, read only export of the owner's Mealime data. |
| `tools/nyt-export` | One time, read only export of the owner's NYT Cooking Recipe Box. |
| `tools/bulk-import` | Bookmarks parsing and inventory, ahead of the in-app bulk URL import. |
| `tools/resource-lint` | Validates the JSON in `Mise/Resources`, which nothing else checks without Xcode. |
| `tools/xcodeproj-lint` | Parses and checks `project.pbxproj`, for sessions with no Xcode. |
| `data/` | Rescued personal data. Git ignored, never committed. |

## Status

Phase 0a is done for Mealime: the rescue ran on 2026-09-14 and the data is in
`data/mealime/`, which is git ignored.

`tools/nyt-export` has run: 96 of about 163 recipes are in `data/nyt/`, parked
short of complete on purpose, see `TODO.md`. `tools/bulk-import` is written and
tested but has not been run against a real bookmarks file.

Phase 0b is written but has never been compiled. It was built in a cloud
session with no Swift toolchain and no Xcode, so the project, the models, the
repositories, the seed loader and the tests all exist and none of them have been
through a compiler. Opening it on the Mac and running the tests is the first
thing to do. `PHASE-0B.md` is the handoff that describes the phase.

See `TODO.md`.

## Getting started

```sh
open Mise.xcodeproj
```

Requires Xcode 16 or newer, and builds against an iOS 18 deployment target. The
project uses Xcode's synchronized file groups, so files added on disk appear in
the project without editing the project file.
