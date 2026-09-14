# Browser rescue

This is the main path, not a fallback. It ran for real on 2026-09-14.

## rescue-state.js, the one to use

The web app loads your whole account into React state. This script reads it
from there, strips the auth token, fetches your favourites from the recipe CDN,
and downloads one file.

1. Sign in at <https://my.mealime.com>.
2. Open the console (Cmd+Option+J in Chrome) and paste
   [`rescue-state.js`](rescue-state.js).
3. Run `__miseState.rescue()`. It downloads `mealime-rescue.json`.
4. Back in a terminal:

   ```sh
   node browser/convert.mjs --in ~/Downloads/mealime-rescue.json
   node src/cli.mjs normalize --include-mealime-content
   ```

That gets you every favourite (full Mealime recipe JSON), every recipe you
imported yourself (full text, ingredients, source link), your collections,
manual grocery items, preferences, notes, ratings, and cook history from every
past plan.

## rescue-images.js, for the photos

The photo host only answers your browser, so the photos come out through a tab
on that host:

1. `node src/cli.mjs image-paths > paths.json`
2. Open any photo from the export in a tab, for example
   <https://cdn-uploads.mealime.com/uploads/recipe/thumbnail/534/thumbnail_f57e494e-7e4c-435c-a3a4-a653dfdcd7a1.jpg>
3. Paste [`rescue-images.js`](rescue-images.js) into the console, then
   `__miseImages.rescue(<contents of paths.json>)`.
4. Click the green button. It saves `mealime-images.zip`.
5. `node src/cli.mjs images --from-zip ~/Downloads/mealime-images.zip`

## The older scripts

`rescue.js` scraped uuids from page HTML. Most of what it found were not
recipes, which is why the CDN answered 403 for all of them. It is kept for
reference only. `collect-localstorage.js` still works as a slow fallback: the
web app caches each recipe you open under `localStorage["mealime/recipes/<uuid>"]`.
`capture-api-calls.js` records what the web app requests, which is how the
`get_user` call was found.

## Reference for the older scripts

### capture-api-calls.js, for inspecting what the site does

If `npm run discover` returns 404 for every route, the paths it tries are wrong.
They are guesses: Mealime's API is not documented, so the script probes for it.
A fresh token will not help, because the routes do not exist.

The web app knows the real routes, so watch it make the calls.

1. Sign in at <https://my.mealime.com>.
2. Open the browser console (Cmd+Option+J in Chrome).
3. Paste the whole of [`capture-api-calls.js`](capture-api-calls.js).
4. Click around: meal plan, grocery list, favorites, Your Recipes, and a few
   individual recipes.
5. Run `__mealimeCapture.dump()`. It prints a summary and copies it to your
   clipboard.

Token values are redacted, so the summary is safe to paste into an issue. It
keeps the header name and the scheme word, which is what the export script needs
in order to authenticate the same way the web app does.

Send that in, or use it to fix `IDENTITY_CANDIDATES` and `COLLECTION_CANDIDATES`
in `../src/discover.mjs` yourself.

### collect-localstorage.js, if the CDN path fails

Use this if the API cannot be made to work at all.

The Mealime web app caches every recipe you open in your browser, under
localStorage keys shaped like `mealime/recipes/<uuid>`. So opening your recipes
once and then dumping localStorage rescues the same data by hand.

The catch: a recipe you never open is not cached, and will not be rescued. You
have to visit them.

### Steps

1. Sign in at <https://my.mealime.com>.
2. Open every recipe you care about, favorites and your own imports both. Give
   each one a second to load.
3. Open the browser console on my.mealime.com.
4. Paste the whole of [`collect-localstorage.js`](collect-localstorage.js) and
   press enter. A `localstorage-dump.json` file downloads.
5. Save it into `data/mealime/` at the repository root.
6. Convert it into the same layout the API export produces:

   ```sh
   node browser/convert.mjs --in ../../data/mealime/localstorage-dump.json
   npm run normalize
   ```

The collector only reads. It never writes to or clears localStorage.
