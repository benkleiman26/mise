// Browser fallback for the Mealime rescue.
//
// Use this only if `npm run discover` cannot authenticate against the API. The
// Mealime web app caches every recipe you open under localStorage keys shaped
// like "mealime/recipes/<uuid>", so opening each recipe once and then dumping
// localStorage rescues the same data by hand.
//
// How to use:
//   1. Sign in at https://my.mealime.com and open every recipe you care about,
//      both favorites and your own imports. A recipe you never open is not
//      cached and will not be rescued.
//   2. Open the browser console on my.mealime.com.
//   3. Paste this whole file and press enter. A file downloads.
//   4. Save it as data/mealime/localstorage-dump.json in the repo.
//   5. Run: node browser/convert.mjs --in data/mealime/localstorage-dump.json
//
// This script only reads. It never writes to or clears localStorage.

(function collectMealimeCache() {
  const entries = {};
  let recipeCount = 0;

  for (let i = 0; i < localStorage.length; i += 1) {
    const key = localStorage.key(i);
    if (!key) continue;
    // Take anything Mealime scoped, not just recipes. Favorites and the grocery
    // list may be cached under sibling keys and we would rather have too much.
    if (!/mealime/i.test(key)) continue;
    const value = localStorage.getItem(key);
    entries[key] = value;
    if (/mealime\/recipes\//i.test(key)) recipeCount += 1;
  }

  const dump = {
    collectedAt: new Date().toISOString(),
    origin: location.origin,
    keyCount: Object.keys(entries).length,
    recipeCount,
    entries,
  };

  console.log(`Collected ${dump.keyCount} keys, ${recipeCount} of them recipes.`);
  if (recipeCount === 0) {
    console.warn('No cached recipes found. Open some recipes first, then run this again.');
  }

  const blob = new Blob([JSON.stringify(dump, null, 2)], { type: 'application/json' });
  const link = document.createElement('a');
  link.href = URL.createObjectURL(blob);
  link.download = 'localstorage-dump.json';
  document.body.appendChild(link);
  link.click();
  link.remove();

  return dump;
})();
