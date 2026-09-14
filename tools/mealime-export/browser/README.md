# Browser fallback

Two scripts here, for two different problems.

## capture-api-calls.js, when discover finds nothing

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

## collect-localstorage.js, when the API is a dead end

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
