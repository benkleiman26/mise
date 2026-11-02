# nyt-import

Fetch the full text of your saved NYT Cooking recipes and turn them into a file
Mise can import.

The export in [`../nyt-export`](../nyt-export) captured urls, folders and cooked
flags only, because the Recipe Box renders client side and there is no API.
This is the other half: the recipe pages are behind your subscription, so the
fetching runs in your own signed-in browser and the reshaping runs here.

## Run it

**1. Print the command to paste.**

```sh
cd tools/nyt-import
npm test
npm run urls | pbcopy
```

That reads the Recipe Box export in `data/nyt/`, pulls every recipe url out of
it with its folders and cooked flag, and copies a one line command to your
clipboard.

**2. Fetch, in the browser.**

Sign in at <https://cooking.nytimes.com>, open the console (Cmd+Option+J in
Chrome), paste the whole of
[`../nyt-export/browser/fetch-recipes.js`](../nyt-export/browser/fetch-recipes.js),
then paste the command from your clipboard.

It goes at about two recipes a second, prints progress every ten, and does not
stop for a page that fails. When it is done:

```js
__nyt.status()          // what it has
__nyt.retryFailures()   // just the ones that did not work
__nyt.rescue()          // downloads nyt-recipes.json
```

**3. Convert.**

```sh
npm run convert
```

Reads `~/Downloads/nyt-recipes.json` and writes `data/mise/nyt_import.json`.
Pass `--in` and `--out` to use other paths.

**4. Import**, in the app: Plan, gear, Import, and pick the file.

## It is read only

The browser script issues GET requests, to `cooking.nytimes.com` only, both
checked in code. It cannot save, unsave, rate or change anything in your Recipe
Box. Nothing is uploaded anywhere: your recipes go from the page to a file on
your disk.

## What it does and does not do

It reshapes schema.org Recipe JSON-LD into Mise's import format. It does not
parse ingredient lines: "4 garlic cloves, thinly sliced" comes out of here as
that string, and `IngredientParser` in the app turns it into a quantity, a unit,
a name and a preparation. One parser, one set of answers.

NYT publishes instructions three different ways, as plain strings, as
`HowToStep` objects and as `HowToSection`s with steps nested inside. All three
are handled.

When a recipe publishes a total time but no breakdown, the total goes in the
cook time, so prep plus cook equals what NYT said rather than double it.

Recipe ids come out of the url, so reimporting updates rather than duplicating
even if a recipe is retitled.

Images are recorded as urls and not downloaded. NYT's images are theirs.
