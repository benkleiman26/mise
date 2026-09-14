// Mealime rescue, version 2: read the web app's own state.
//
// Paste this whole file into the console on https://my.mealime.com while
// signed in, then run __miseState.rescue(). It downloads mealime-rescue.json.
//
// Why this works where rescue.js did not: my.mealime.com is a React app that
// loads the whole account with one POST to api.mealime.com/api/v2/get_user
// and keeps the result in component state. That object carries the user's
// favourites (with the published_recipe_uuid that cdn-recipes.mealime.com is
// keyed by), every recipe the user imported (full text, ingredients, source
// url, images), the current meal plan and grocery list, 300 past plans,
// collections, notes, and ratings. Nothing has to be scraped from HTML.
//
// The 295 uuids the old scan found were mostly not recipes at all, which is why
// the CDN answered 403 (S3 says 403, not 404, for keys it will not list). Real
// published recipe uuids fetch fine with no credentials.
//
// Read only. Nothing here writes to Mealime.

(() => {
  const CDN = 'https://cdn-recipes.mealime.com';
  // Fields that must not leave the browser. The auth token is the account.
  const SECRET_KEYS = new Set(['auth_token', 'ios_receipt_check', 'tracking_id', 'last_modified_client_id', 'share_token']);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  /** Walks the React fiber tree and returns the account object. */
  function findAccount() {
    const rootEl = document.getElementById('root');
    const key = Object.keys(rootEl).find((k) => k.startsWith('__reactContainer'));
    let root = rootEl[key];
    while (root.return) root = root.return;
    const seen = new Set();
    let found = null;
    const look = (v, depth) => {
      if (found || !v || typeof v !== 'object' || seen.has(v) || depth > 8) return;
      seen.add(v);
      if (v.favourites && v.current_meal_plan && v.user_recipes) {
        found = v;
        return;
      }
      if (Array.isArray(v)) {
        for (const x of v) look(x, depth + 1);
        return;
      }
      for (const k of Object.keys(v)) {
        if (['return', 'child', 'sibling', 'alternate', 'stateNode'].includes(k) || k.startsWith('_')) continue;
        look(v[k], depth + 1);
      }
    };
    const stack = [root];
    while (stack.length && !found) {
      const fiber = stack.pop();
      if (fiber.memoizedState) look(fiber.memoizedState, 0);
      if (fiber.memoizedProps) look(fiber.memoizedProps, 0);
      if (fiber.child) stack.push(fiber.child);
      if (fiber.sibling) stack.push(fiber.sibling);
    }
    return found;
  }

  async function fetchPublished(uuids, { concurrency = 3, delayMs = 200 } = {}) {
    const raw = {};
    const failed = [];
    for (let i = 0; i < uuids.length; i += concurrency) {
      await Promise.all(
        uuids.slice(i, i + concurrency).map(async (id) => {
          try {
            const r = await fetch(`${CDN}/${id}.json`);
            if (r.ok) raw[id] = await r.text();
            else failed.push({ id, status: r.status });
          } catch (error) {
            failed.push({ id, error: String(error.message ?? error) });
          }
        })
      );
      await sleep(delayMs);
    }
    return { raw, failed };
  }

  function download(name, text) {
    const blob = new Blob([text], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  async function rescue() {
    const user = findAccount();
    if (!user) {
      console.error('Could not find the account in page state. Are you signed in on my.mealime.com?');
      return null;
    }
    const uuids = [
      ...new Set(
        [...user.favourites.map((f) => f.published_recipe_uuid), ...(user.current_meal_plan.meals || []).map((m) => m.published_recipe_uuid)].filter(Boolean)
      ),
    ];
    console.log(`Fetching ${uuids.length} published recipes from ${CDN}`);
    const { raw, failed } = await fetchPublished(uuids);

    const account = {};
    for (const [k, v] of Object.entries(user)) {
      if (SECRET_KEYS.has(k) || k === 'user_recipes') continue;
      account[k] = v;
    }
    const recipes = {};
    for (const [id, text] of Object.entries(raw)) recipes[id] = JSON.parse(text);
    const favIds = new Set(user.favourites.map((f) => f.published_recipe_uuid));
    const sources = {};
    for (const id of Object.keys(recipes)) sources[id] = { sources: [favIds.has(id) ? '/favorites' : '/current-plan'] };

    const dump = {
      format: 'mealime-rescue',
      version: 2,
      collectedAt: new Date().toISOString(),
      origin: location.origin,
      method: 'react-state plus cdn-recipes fetch',
      counts: {
        favourites: user.favourites.length,
        publishedRecipesFetched: Object.keys(recipes).length,
        userRecipes: user.user_recipes.length,
        userRecipesDeleted: user.user_recipes.filter((r) => r.is_deleted).length,
        historyPlans: (user.history || []).length,
        collections: (user.collections || []).length,
      },
      sources,
      pages: {},
      recipes,
      rawRecipeText: raw,
      userRecipes: user.user_recipes,
      account,
      failed,
    };
    download('mealime-rescue.json', JSON.stringify(dump, null, 2));
    console.log(`%cRescued ${dump.counts.publishedRecipesFetched} published and ${dump.counts.userRecipes} own recipes. Downloaded mealime-rescue.json`, 'color: green; font-weight: bold');
    if (failed.length) console.warn('Failed:', failed);
    return dump.counts;
  }

  window.__miseState = { rescue, findAccount };
  console.log('Run __miseState.rescue() to download your Mealime data.');
})();
