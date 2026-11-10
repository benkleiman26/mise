# Writing recipes for Mise

How to add recipes by hand, in a form the app can actually install. Written so
it can be handed to an assistant working on the recipe files alone, with no
other context.

## Where they go

`Mise/Resources/seed_recipes.json`. The file has four top level keys: `format`,
`version`, `note` and `recipes`. Only `recipes` changes; append to that array.

## This file is redistributed, so only put original recipes in it

Everybody who installs Mise gets this file, including households that are not
the owner's. That makes it the one place in the project where copyright is a
live question.

Write recipes in your own words, or adapt a technique into new prose. Do not
paste in the text of a published recipe. The owner's own library of about 400
rescued New York Times recipes is in `data/`, is git ignored, and must never be
moved into this file for exactly this reason.

## The shape of one recipe

```json
{
  "id": "seed-sheet-pan-salmon",
  "title": "Sheet Pan Salmon and Green Beans",
  "summary": "Salmon and green beans roast together on one pan while the oven does the work.",
  "sourceType": "builtIn",
  "prepMinutes": 8,
  "cookMinutes": 16,
  "totalMinutes": 24,
  "baseServings": 4,
  "tags": ["seafood", "sheet pan", "under 30", "kid friendly", "pescetarian"],
  "cookware": ["sheet pan"],
  "ingredients": [
    { "name": "salmon fillet", "canonicalItem": "salmon", "quantity": 1.5, "unit": "lb" },
    { "name": "garlic, minced", "canonicalItem": "garlic", "quantity": 2, "unit": "clove" }
  ],
  "steps": [
    { "text": "Heat the oven to 425F and put a sheet pan inside while it heats.", "ingredientRefs": [] },
    { "text": "Pat the salmon dry and season it well.", "ingredientRefs": ["salmon"], "timerSeconds": 780 }
  ]
}
```

`id` is permanent. Record ids are derived from it, so changing the id of a
recipe that has already shipped does not rename it, it creates a second copy on
every phone. Use `seed-` and a slug of the title.

`sourceType` is `builtIn` for anything written here. The other values
(`imported`, `manual`, `aiGenerated`) belong to recipes the app creates.

`name` is the line as a cook would read it, including how it is cut: "garlic,
minced". `canonicalItem` is the shopping entry it adds up into, so four recipes
wanting garlic produce one line on the list.

`ingredientRefs` holds `canonicalItem` values used in that step, not `name`
values. It drives the highlight in the cook view, so getting it wrong is
cosmetic rather than fatal.

`timerSeconds` is optional and only for steps with a real wait.

## The vocabularies, which are closed sets

`unit` must be one of: `count`, `tsp`, `tbsp`, `cup`, `floz`, `oz`, `lb`, `g`,
`kg`, `ml`, `l`, `pinch`, `clove`, `can`, `bunch`, `package`. Anything else is
dropped silently when it syncs.

`canonicalItem` must already exist in `Mise/Resources/canonical_items.json`,
which holds 395 of them. Check before inventing one. If a recipe genuinely
needs something new, add it there in the same change:

```json
{ "name": "baguette", "aisle": "bakery", "aliases": ["french bread"], "defaultUnit": "count" }
```

Names are lowercase and singular. `aisle` is one of: `produce`, `meat`,
`seafood`, `deliAndCheese`, `dairyAndEggs`, `bakery`, `frozen`,
`nutButtersAndJams`, `bakingAndSpices`, `riceGrainsBeans`, `cannedAndJarred`,
`pastaAndSauces`, `oilsAndCondiments`, `international`, `snacks`, `beverages`,
`household`, `other`.

`tags` are free text and lowercase. Existing ones are worth reusing: a diet
tag where it applies (`vegetarian`, `vegan`, `pescetarian`), a time tag
(`under 30`), a method tag (`sheet pan`, `one pot`), and `kid friendly`.

## Validate before committing

```sh
cd tools/resource-lint && npm run lint
```

It parses both files, checks every unit and aisle, and resolves every
ingredient line through the real matcher to confirm it lands on the
`canonicalItem` the recipe claims. A line that resolves somewhere else is the
failure that matters, because in the app it silently merges into the wrong
grocery entry. The lint must end in "All good."

## What happens to a recipe once it is added

`SeedInstaller` runs on every launch, not only the first. It decides what to
install by derived id rather than by a "has seeded" flag, so a recipe added
here arrives on phones that were set up months ago, as soon as they run a build
containing it. Recipes are part of the shared set, so it then syncs to the
other phones in the household too.

Seeded records claim `updatedAt` of epoch 0, the weakest possible claim, so
anything anybody has actually edited always wins over a seeded default.

Adding is the only thing that reaches an existing phone. `installRecipes` skips
any recipe whose derived id is already in the store, so editing a recipe that
has shipped changes nothing for anybody who already has it, and reusing its id
for a different recipe does nothing at all. A changed recipe needs a new id,
and a new id is a second recipe sitting beside the old one.
