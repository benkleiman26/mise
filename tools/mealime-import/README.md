# mealime-import

Turn the rescued Mealime library into one file Mise can import.

The rescue in [`../mealime-export`](../mealime-export) wrote `data/mealime/recipes/*.json`,
one file per recipe, in Mealime's own shape. This reshapes those into Mise's
import format and writes a single file.

It is read only over the rescued files. Mealime shut down on 2026-10-21, so
`data/mealime/` is the only copy of that data in existence.

## Run it

```sh
cd tools/mealime-import
npm test
npm run convert
```

That writes `data/mise/mealime_import.json`.

Then in Mise: **Plan → gear → Import → Import recipes from a file**, and pick it.

Options:

```sh
node src/cli.mjs --in ../../data/mealime/recipes \
                 --out ../../data/mise/mealime_import.json \
                 --default-servings 4
```

## Nothing leaves your machine

The output goes into `data/`, which git ignores. Your recipes are personal and
the Mise repository is public. Do not move that file anywhere inside the
repository that is tracked.

## What it does and does not do

It reshapes. It does not parse.

"2 scallions, trimmed then sliced crosswise 1/4-inch-thick" comes out of here as
that same string. `IngredientParser` in the app turns it into a quantity, a
unit, a name and a preparation, and `CanonicalMatcher` resolves it to a grocery
item so it merges on the list. Both have fixture tests covering lines exactly
like that one. A second parser written in JavaScript here would be a second set
of answers to the same question, and the two would drift apart within a week.

Two shapes appear in the real export and both are handled:

- a recipe you imported into Mealime yourself, where `quantity` is empty and the
  whole line sits in `ingredient_name`
- a recipe Mealime published, where `quantity` is its own field

A recipe is skipped when it has no title, or has neither ingredients nor steps.
The run prints what it skipped and why.

`serving_count` and `cooking_minutes` are null on recipes you typed in yourself.
Servings fall back to four. Cooking time stays zero, which the app reads as
"not recorded" rather than inventing a number for a screen that says "26 min".

Images are not handled yet. The rescued photos are in `data/mealime/images/`.

## Importing twice

Safe. Every record's id is derived from its Mealime id, so a second import
replaces those recipes rather than adding a second library. The app reports how
many were added and how many replaced.
