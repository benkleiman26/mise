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
| `data/` | Rescued personal data. Git ignored by default. |

## Status

Phase 0a is written and tested, but has not been run against a live Mealime
account yet. That needs the owner's auth token and must happen before Mealime
deletes account data on October 21, 2026.

Phase 0b has not started. See `TODO.md`.

## Getting started

```sh
open Mise/Mise.xcodeproj
```

Requires Xcode 16 or newer. The project uses Xcode's synchronized file groups, so
files added on disk appear in the project without editing the project file.
