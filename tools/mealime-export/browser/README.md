# Browser fallback

Use this only if `npm run discover` cannot authenticate against the Mealime API.

The Mealime web app caches every recipe you open in your browser, under
localStorage keys shaped like `mealime/recipes/<uuid>`. So opening your recipes
once and then dumping localStorage rescues the same data by hand.

The catch: a recipe you never open is not cached, and will not be rescued. You
have to visit them.

## Steps

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
