// Fetch the full text of your saved NYT Cooking recipes, in your own browser.
//
// The Recipe Box export captured urls, folders and cooked flags only, because
// there is no API and the box renders client side. This is the other half: it
// opens each recipe page the way you would, reads the schema.org Recipe that
// NYT publishes in the page, and downloads the lot as one JSON file.
//
// It runs here rather than on a server because these pages are behind your
// subscription. Nothing is uploaded anywhere.
//
// READ ONLY. GET requests, to cooking.nytimes.com only, both enforced below.
// It cannot save, unsave, rate or change anything in your Recipe Box.
//
//   1. Sign in at https://cooking.nytimes.com and stay on that site.
//   2. Open the console (Cmd+Option+J in Chrome) and paste this whole file.
//   3. Paste the command that `npm run urls` printed, which is
//      __nyt.fetchAll([ ...your recipe urls... ])
//   4. When it finishes, __nyt.rescue() downloads nyt-recipes.json.
//
// It goes at about two recipes a second and stops on nothing: a page that
// fails is recorded with its reason and the run carries on.

(() => {
  const HOST = 'cooking.nytimes.com';
  const PAUSE_MS = 400;

  // Everything collected so far. Memory is the source of truth, and rescue()
  // writes from this same object, because a previous tool counted one place
  // and downloaded from another and the two disagreed by 67 recipes.
  const state = { recipes: [], failures: [], startedAt: null };

  function sameSite(url) {
    try {
      const parsed = new URL(url, location.origin);
      return parsed.protocol === 'https:' && parsed.hostname === HOST;
    } catch {
      return false;
    }
  }

  async function getPage(url) {
    if (!sameSite(url)) throw new Error(`refusing a url outside ${HOST}`);
    const response = await fetch(url, {
      method: 'GET',
      credentials: 'include',
      redirect: 'follow',
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return response.text();
  }

  /** The schema.org Recipe in a page, wherever it is hiding. */
  function readRecipe(html) {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const blocks = [...doc.querySelectorAll('script[type="application/ld+json"]')];

    for (const block of blocks) {
      let parsed;
      try {
        parsed = JSON.parse(block.textContent);
      } catch {
        continue;
      }
      const found = findRecipe(parsed);
      if (found) return found;
    }
    return null;
  }

  function findRecipe(node) {
    if (!node || typeof node !== 'object') return null;
    if (Array.isArray(node)) {
      for (const child of node) {
        const found = findRecipe(child);
        if (found) return found;
      }
      return null;
    }
    const type = node['@type'];
    const isRecipe = type === 'Recipe' || (Array.isArray(type) && type.includes('Recipe'));
    if (isRecipe) return node;
    if (node['@graph']) return findRecipe(node['@graph']);
    return null;
  }

  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  async function fetchAll(entries) {
    const list = (Array.isArray(entries) ? entries : [])
      .map((entry) => (typeof entry === 'string' ? { url: entry } : entry))
      .filter((entry) => entry && typeof entry.url === 'string');

    if (list.length === 0) {
      console.error('Nothing to fetch. Pass the array that `npm run urls` printed.');
      return;
    }

    state.recipes = [];
    state.failures = [];
    state.startedAt = new Date().toISOString();

    console.log(`%cFetching ${list.length} recipes. Leave this tab open.`, 'font-weight: bold');

    for (const [index, entry] of list.entries()) {
      try {
        const jsonld = readRecipe(await getPage(entry.url));
        if (!jsonld) throw new Error('no schema.org Recipe in the page');
        state.recipes.push({
          url: entry.url,
          folders: entry.folders ?? [],
          cooked: entry.cooked === true,
          jsonld,
        });
      } catch (error) {
        state.failures.push({ url: entry.url, why: String(error.message ?? error) });
      }

      const done = index + 1;
      if (done % 10 === 0 || done === list.length) {
        console.log(`${done}/${list.length}  kept ${state.recipes.length}  failed ${state.failures.length}`);
      }
      await sleep(PAUSE_MS);
    }

    console.log(
      `%cDone. ${state.recipes.length} recipes, ${state.failures.length} failures. Run __nyt.rescue() to download.`,
      'color: green; font-weight: bold'
    );
    if (state.failures.length) console.table(state.failures);
  }

  function rescue() {
    if (state.recipes.length === 0) {
      console.error('Nothing collected yet. Run __nyt.fetchAll([...]) first.');
      return;
    }
    const payload = {
      format: 'nyt-recipe-fetch',
      version: 1,
      fetchedAt: state.startedAt,
      counts: { recipes: state.recipes.length, failures: state.failures.length },
      failures: state.failures,
      recipes: state.recipes,
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'nyt-recipes.json';
    link.click();
    console.log(`%cDownloaded nyt-recipes.json with ${state.recipes.length} recipes.`, 'color: green; font-weight: bold');
  }

  function status() {
    console.log(`collected ${state.recipes.length}, failed ${state.failures.length}`);
    return { recipes: state.recipes.length, failures: state.failures.length };
  }

  /** Retries only the ones that failed, which is usually a handful. */
  async function retryFailures() {
    const again = state.failures.map((failure) => ({ url: failure.url }));
    if (again.length === 0) return console.log('nothing failed');
    const kept = state.recipes;
    await fetchAll(again);
    state.recipes = [...kept, ...state.recipes];
    console.log(`now holding ${state.recipes.length} recipes`);
  }

  window.__nyt = { fetchAll, rescue, status, retryFailures, state };
  console.log('%cReady. Paste the __nyt.fetchAll([...]) line that `npm run urls` printed.', 'font-weight: bold');
})();
