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
| `Mise/` | The Xcode project. iOS 17 minimum, SwiftUI, SwiftData locally, Supabase backend. |
| `Mise/Mise/App` | Entry point, dependency container, root tab bar. |
| `Mise/Mise/Features` | One folder per feature: Plan, GroceryList, Recipes, Pantry, CookMode, Settings. |
| `Mise/Mise/Domain/Models` | SwiftData `@Model` classes. |
| `Mise/Mise/Domain/Services` | Pure logic. List generation, parsing, unit conversion. |
| `Mise/Mise/Domain/Repositories` | Protocols plus SwiftData implementations. |
| `Mise/Mise/Resources` | `seed_recipes.json`, `canonical_items.json`, AI prompts. |
| `Mise/MiseTests` | XCTest target. |
| `tools/mealime-export` | One time, read only export of the owner's Mealime data. |
| `tools/nyt-export` | One time, read only export of the owner's NYT Cooking Recipe Box. |
| `tools/bulk-import` | Bookmarks parsing and inventory, ahead of the in-app bulk URL import. |
| `tools/resource-lint` | Validates the JSON in `Mise/Resources`, which nothing else checks without Xcode. |
| `data/` | Rescued personal data. Git ignored, never committed. |

## Status

Phase 0a is done for Mealime: the rescue ran on 2026-09-14 and the data is in
`data/mealime/`, which is git ignored.

`tools/nyt-export` and `tools/bulk-import` are written and tested but have not
been run against the real NYT Cooking site or a real bookmarks file yet.

Phase 0b has not started in Xcode. Everything in it that does not need a
compiler is done: `Mise/Resources/canonical_items.json` (297 items, 71 staples)
and `seed_recipes.json` (12 recipes), both validated by `tools/resource-lint`.
`PHASE-0B.md` is the handoff for a Mac session.

See `TODO.md`.

## Getting started

```sh
open Mise/Mise.xcodeproj
```

Requires Xcode 16 or newer. The project uses Xcode's synchronized file groups, so
files added on disk appear in the project without editing the project file.
