# Handoff: Phase 0b, the skeleton

For a Claude Code session running on the owner's Mac, where Xcode is.

## Why this is not being done in the cloud

The cloud session has no Swift toolchain and no Xcode, so it cannot compile a
line of this. Writing a few hundred lines of SwiftUI and SwiftData blind and
handing over the error list is a bad trade when the Mac is right there. That
session built everything that does not need a compiler, listed below, so this
one can go straight at the app.

## How to start

```sh
git clone https://github.com/benkleiman26/mise && cd mise   # or: cd ~/mise && git pull
```

Read, in this order:

1. The build spec, which is the single source of truth and is still being
   edited: <https://docs.google.com/document/d/11xXFBZrQxdpB-XnxpqPGV71n2Sxlkd2PdANPpr2aov0/edit>
   Sections 3, 4, 7, 8, 9 and 11 are the ones this phase needs.
2. `DECISIONS.md`, for choices already made and why.
3. `TODO.md`, for known gaps.

Section 9 says: work one phase at a time, and at the end of the phase all tests
pass, the app builds and runs in the simulator, and you write a short summary of
what was built and what is stubbed. Then stop and wait for review. Hold to that.
Phase 0b is the skeleton and nothing more. Resist building Phase 1 features
because they are in front of you.

## What Phase 0b is

From section 9, verbatim in substance:

- Xcode project
- Tab bar
- SwiftData container with all models
- Repository protocols
- Seed loader that imports `seed_recipes.json` and `canonical_items.json` on
  first launch
- Empty states for every tab
- Unit test target wired up

That is the whole phase. No list generation, no parsing, no import, no cook
mode.

## What already exists, so do not rebuild it

`Mise/Resources/canonical_items.json`
: 297 canonical grocery items across the 18 aisles from section 4, with
  aliases, default units, and 71 staple flags. The staples from section 12 are
  all marked. This is what the list generator resolves ingredient names against
  in Phase 2, and what the pantry pre-seeds from.

`Mise/Resources/seed_recipes.json`
: 12 original recipes, every ingredient linked to a canonical item and every
  step carrying `ingredientRefs` so the section 5.5 cook view works. Section 5.1
  asks for 40 to 60; the rest are Phase 1. The loader should not care how many
  there are.

`tools/resource-lint`
: Validates both files. Run `npm test` and `npm run lint` there after any edit
  to them. It catches duplicate aliases, unknown aisles and units, ingredients
  that resolve to nothing, step refs that point at missing ingredients, and em
  dashes. Keep it passing; it is the only check those files get outside the app.

`tools/mealime-export`, `tools/nyt-export`, `tools/bulk-import`
: Done or in progress, and not this phase's business.

The owner's rescued Mealime data is in `data/`, which is git ignored. **Do not
commit anything from `data/`.** The repository is public.

## The toolchain, and a deployment target question

Confirmed on the owner's Mac on 2026-09-15: **Xcode 27.0** (build 27A266a), with
**iOS 26.5** simulator runtimes installed (iPhone 17 family, iPhone Air, iPad
Pro M5). That is far ahead of anything this repository assumes, so two things
follow.

**No iOS 17 runtime is installed.** Building with a deployment target of iOS 17
and running on an iOS 26.5 simulator is fine and normal, so this does not block
anything. It does mean nothing is ever exercised on the actual floor. If the
minimum stays at iOS 17, install that runtime before the TestFlight build in
Phase 5, or the first real device on an old OS is where problems surface.

**The minimum deserves a fresh decision.** Section 3 says iOS 17+, written when
that was one version back. It is now several. Section 12 asks the owner to
confirm the minimum is acceptable for his devices, and that question is
genuinely live rather than a formality:

- Staying at iOS 17 means availability checks around anything newer, and
  SwiftData's earliest release, which was its roughest.
- Raising the floor removes that friction and simplifies the models written in
  this phase, at the cost of excluding older phones. Section 0 aims at Mealime's
  audience, not just the owner, and some of them are on old hardware.

This is cheap to decide now and expensive to revisit once every model and view
has been written against one answer. **Ask the owner before writing the models.**
Do not pick a floor unilaterally.

Whichever floor is chosen, put it in the spec's section 3 rather than only in
the Xcode project, and note it in `DECISIONS.md`.

## Things worth deciding well

**Models.** Section 4 lists them: Recipe, Ingredient, Step, canonical grocery
item, PantryEntry, MealPlan, PlannedMeal, GroceryList, GroceryItem, Household,
User, HouseholdPreferences, plus the Aisle, Unit, Restriction and menu type
enums. Every entity carries `id: UUID`, `householdID: UUID`, `createdAt`,
`updatedAt`. Section 4 says keep them thin and put logic in services, so resist
adding computed behavior beyond `totalMinutes`.

`householdID` on everything is not decoration. Section 2 says multi-user ready,
single-user shipped, and section 9's Phase 5 turns on Supabase with row level
security keyed on it. v1 seeds exactly one household and shows no sign-in.

**Repositories.** Section 3 says keep all persistence behind a Repository
protocol so the backing store can be swapped, and that the first build can run
entirely on the local store with sync stubbed. So: protocol per aggregate, a
SwiftData implementation behind it, and nothing in a view that touches a
`ModelContext` directly.

**Seeding.** First launch imports both JSON files and creates the one household
with the preferences from section 4: pescetarian, no restrictions, dislikes
olives, 4 servings, US units. Staples get a PantryEntry of `have`, which is what
keeps salt and olive oil off every list. Make it idempotent and keyed off
something stable, because it will be run repeatedly in the simulator.

**Empty states.** Section 7 wants four tabs, Plan, List, Recipes and Pantry,
with Settings behind a gear on Plan. Section 0 says onboarding and empty states
must work for a stranger, not just the owner, so write real copy rather than
"No items". Cook mode is presented full screen modally and is Phase 3.

## An open question to put to the owner, not to decide alone

The cloud session recommended extracting `ListGenerator`, `IngredientParser`,
`UnitConverter` and `CanonicalMatcher` into a `MiseCore` Swift package with no
SwiftUI or SwiftData imports, so the grocery list math compiles and tests
anywhere, including in cloud sessions. Section 2 calls the list the hero and
section 3 says its math must be exhaustively tested.

The owner has not folded that into the spec: section 8 still puts those services
inside the app target. So **do not create the package on your own initiative.**
Those services are Phase 1 and Phase 2 work anyway. If it comes up, put it to
the owner as a spec change.

What Phase 0b should do either way is keep `Domain/Services` free of SwiftUI and
SwiftData imports, so the split stays cheap if it is ever made.

## Conventions, enforced

From section 11:

- **No em dashes** anywhere: code, comments, docs, commit messages, UI copy.
  Commas, colons, or periods.
- Commit after each meaningful unit of work, explaining why and not just what.
  Never leave the project non-building at a commit.
- Small files. Pure functions in `Domain/Services`. No business logic in views.
- No third party dependencies without a line in `DECISIONS.md` giving the
  reason. Prefer Apple frameworks.
- Decisions the spec does not cover go in `DECISIONS.md`, and work continues.
  Known gaps go in `TODO.md`.
- Section 7: use SwiftUI defaults well, do not build a custom design system.
  Dynamic Type, light and dark mode, SF Symbols.

## Needed from the owner before you finish

Both are in section 12 and are already in `TODO.md`:

- Bundle identifier, suggested `com.<yourdomain>.mise`, and the Apple Developer
  team ID.
- Confirmation that iOS 17 is an acceptable minimum for his devices.

Neither blocks starting. Use a placeholder bundle id and say so in the summary.

## Done means

- The project opens in Xcode and runs in the simulator.
- Four tabs, each with a real empty state, and Settings reachable from Plan.
- Every model from section 4 exists and the SwiftData container builds with all
  of them registered.
- First launch seeds one household, 297 canonical items, 12 recipes, and pantry
  entries for the staples. Second launch does not duplicate any of it.
- Repository protocols exist with SwiftData implementations behind them.
- The unit test target runs, with at least a test that seeding is idempotent and
  that every seeded ingredient resolved to a canonical item.
- `cd tools/resource-lint && npm test` still passes.
- Committed and pushed to `main`, with nothing from `data/`.
- A short summary of what was built and what is stubbed, then stop for review.
