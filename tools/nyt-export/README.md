# nyt-export

A one time, read only export of your NYT Cooking Recipe Box.

It produces `data/nyt/nyt_recipe_box.json`: every saved recipe's URL, which
folders it is in, and whether it is in your Cooked Recipes list. The app imports
that file later and fetches each recipe itself through the JSON-LD pipeline, so
this only has to capture what the app cannot work out on its own.

There is no public NYT API for the Recipe Box, so the collecting runs in your
own signed-in browser. Nothing is uploaded anywhere, and nothing in your Recipe
Box is added to, removed, or marked.

## Collect

1. Sign in at <https://cooking.nytimes.com> and open your Recipe Box.
2. Open the console (Cmd+Option+J in Chrome) and paste the whole of
   [`browser/collect.js`](browser/collect.js).
3. Run the steps it prints:

   ```js
   __nyt.collect()  // walks every list, page by page. this is the one to use
   __nyt.status()   // counts, by folder
   __nyt.rescue()   // downloads nyt-recipe-box-raw.json
   ```

   `__nyt.probe()` inspects the page you are on, and `__nyt.scan()` harvests
   just that page, for anything `collect()` misses.

Start with `probe()`. It reports which of three strategies found anything: the
Next.js hydration payload, the rendered DOM, and raw link matching. As observed
on 2026-09-14 the DOM and raw matching each found all 48 recipes on a page while
the hydration payload found none, so the DOM is what actually carries the list.
**If all three return zero, do not guess: send the `probe()` output to whoever is
building this.**

**The Recipe Box is rendered client side.** Fetching a page returns an empty
shell with no recipes in it, so `collect()` loads each page in a hidden
same-origin frame and lets the page's own JavaScript build the list, the same
way opening it yourself would. `crawl()`, which fetches HTML directly, is kept
only because it may suit a differently built page; on the Recipe Box it finds
nothing and says so.

It paginates with `?page=2` and onward rather than scrolling forever, and folder
urls are numeric ids such as `/recipe-box/38271228`, so the folder's real name
comes from the text of the link pointing at it, with the item count stripped off
the end.

If framing is blocked, fall back to doing it by hand: open each list, paste the
script again, and run `__nyt.scan()`.

**Recently Viewed is never collected.** It lists recipes you opened rather than
saved, and importing it would fill the library with things you never chose.
`__nyt.scan({ force: true })` overrides that if you ever want them.

`scan()` scrolls to the bottom and clicks any "load more" control until the page
stops growing, which matters because the Recipe Box loads lazily. `crawl()`
fetches folder pages directly, which is faster but can miss lazily loaded rows,
so open any folder whose count looks short and run `scan()` there.

Navigating away unloads the script. Paste it again to get the commands back; the
collected recipes survive in sessionStorage for that tab.

## Convert

```sh
cd tools/nyt-export
node src/cli.mjs convert --in ~/Downloads/nyt-recipe-box-raw.json
```

That writes `data/nyt/nyt_recipe_box.json` and prints the counts, the folders,
and the tag each folder maps to. It also warns when the result looks wrong, for
example far fewer recipes than expected or nothing marked cooked.

Read those warnings. A silent partial export is the failure worth catching here.

## What it produces

```json
{
  "format": "nyt-recipe-box",
  "version": 1,
  "counts": { "recipes": 163, "cooked": 41, "folders": 3 },
  "folders": [{ "name": "Easy Kid-Friendly Recipes", "count": 38, "tag": "kid friendly" }],
  "recipes": [
    {
      "id": "1020000",
      "url": "https://cooking.nytimes.com/recipes/1020000-sheet-pan-salmon",
      "title": "Sheet-Pan Salmon",
      "folders": ["Easy Kid-Friendly Recipes"],
      "tags": ["kid friendly"],
      "cooked": true
    }
  ]
}
```

The numeric id is the stable key. The app dedupes on it, so re-running this and
re-importing does not create duplicates.

Folder names become tags, minus filler words. Folders that describe a status
rather than a topic (Cooked Recipes, Recipe Box, Saved) never become tags;
cooked recipes are marked with `cooked` instead, which the app turns into
`timesCooked = 1`.

A record with no title is still fine. The app fetches every page anyway, so the
title, ingredients, steps, and image all come from the recipe's own JSON-LD.

## Tests

```sh
npm test
```

Covers the three extraction strategies against stubbed markup, folder and cooked
detection, merging a recipe that appears in several folders, and the conversion.

## Copyright

Recipes are stored for your own personal use as a subscriber. The app always
shows attribution and a link back, and never shares imported recipes to another
household or includes them in AI prompts. See spec section 5.6a.
