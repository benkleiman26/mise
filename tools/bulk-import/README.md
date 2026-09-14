# bulk-import

Parses a browser bookmarks export and says what is in it, ahead of the bulk URL
import described in spec section 5.6a.

The import itself is an app feature, not a script. This exists for two reasons:

1. **To plan against real numbers.** How many of those open tabs are recipes,
   how many are already in the NYT Recipe Box export, and how many sit on hosts
   that will need the AI extraction fallback. That last number is the expensive
   one, and guessing it wrong sizes Phase 4b wrongly.
2. **To write the parser once.** The Netscape bookmarks format is fiddly:
   invalid HTML, missing closing tags, nested folders implied by nesting rather
   than stated. `src/bookmarks.mjs` is the reference implementation, tested
   against a fixture here, and Phase 4 ports it to Swift against the same cases.

## Use

Put your bookmarks export at `data/bookmarks.html` (Chrome: Bookmarks manager,
then the three dot menu, Export bookmarks), then:

```sh
cd tools/bulk-import
npm run inventory
```

That writes `data/bookmarks_inventory.json` and prints a summary. To look at one
folder only, for example the folder made from the open recipe tabs:

```sh
node src/cli.mjs inventory --folder "Recipes to try"
```

## What it works out

- **Unique URLs.** Duplicates are collapsed by canonical URL, so the same recipe
  bookmarked twice, once with tracking parameters and once with a fragment,
  counts once.
- **Already saved.** A bookmark pointing at a NYT recipe already in
  `data/nyt/nyt_recipe_box.json` is marked, since re-importing it would be a
  duplicate. The app dedupes on the NYT numeric id anyway, per section 5.6a,
  but knowing the overlap up front makes the count honest.
- **Recipe or not.** Search results, social links and code repositories are set
  aside. The guess is deliberately generous: an unknown host with a real path
  counts as a maybe, because skipping a real recipe is worse than one wasted
  fetch. The app still tries every URL it is given.
- **Hosts.** Sorted by count, which is what says whether JSON-LD will cover most
  of the batch or whether the AI fallback carries real weight.

## How this feeds the app

The bulk import in section 5.6a accepts a plain text file of URLs or a bookmarks
export directly, runs every URL through the same pipeline as a share sheet
import, and shows a "needs attention" list at the end for pages it could not
parse. The owner's first batch lands in a **To try** collection.

So the app reads `bookmarks.html` itself. This inventory does not replace that
and is not a required step. It answers the planning questions now, while Phase 4
is still being designed.

## Tests

```sh
npm test
```

The fixture covers nested folders, entity escaping, tracking parameters,
duplicates, a `javascript:` bookmarklet that must be skipped, and non-recipes.
