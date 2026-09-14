// Rescues Mealime recipes from the browser.
//
// There is no REST API. my.mealime.com is server rendered, so the recipe list
// lives in the page HTML, and recipe content is served as static JSON from
// cdn-recipes.mealime.com/<uuid>.json with no authentication at all. That means
// the whole rescue can run in the page, with the session you already have, and
// no token is needed anywhere.
//
// How to use:
//   1. Sign in at https://my.mealime.com.
//   2. Paste this file into the console (Cmd+Option+J in Chrome).
//   3. Run __mise.crawl(). The site is server rendered, so it fetches your other
//      pages itself and reads the ids out of their HTML. No navigating, no
//      re-pasting. Use __mise.scan() by hand for a page the crawl missed.
//   4. Run __mise.rescue(). It fetches every recipe and downloads one file.
//   5. Convert and normalize it:
//        node browser/convert.mjs --in ~/Downloads/mealime-rescue.json
//        npm run normalize
//
// Read only against Mealime. It fetches and reads; the only thing it writes is
// its own key in sessionStorage, which the browser drops when you close the tab.

(() => {
  const KEY = '__miseRescue';
  const CDN = 'https://cdn-recipes.mealime.com';
  const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
  const MAX_PAGE_TEXT = 40000;

  const load = () => {
    try {
      return JSON.parse(sessionStorage.getItem(KEY)) ?? { ids: {}, pages: {} };
    } catch {
      return { ids: {}, pages: {} };
    }
  };
  const save = (state) => {
    try {
      sessionStorage.setItem(KEY, JSON.stringify(state));
    } catch (error) {
      console.warn('Could not persist to sessionStorage, ids will not survive navigation.', error);
    }
  };

  /**
   * Harvests recipe ids from wherever this page happens to keep them: links,
   * inline JSON, data attributes, and the web app's own localStorage cache.
   * Scanning the raw HTML as text catches ids in shapes we have not seen.
   */
  function scan() {
    const state = load();
    const where = location.pathname;
    const before = Object.keys(state.ids).length;

    const add = (id, source) => {
      const key = id.toLowerCase();
      state.ids[key] = state.ids[key] ?? { sources: [] };
      if (!state.ids[key].sources.includes(source)) state.ids[key].sources.push(source);
    };

    for (const match of document.documentElement.innerHTML.matchAll(UUID)) add(match[0], where);
    for (let i = 0; i < localStorage.length; i += 1) {
      const key = localStorage.key(i);
      const found = key?.match(UUID);
      if (found) found.forEach((id) => add(id, 'localStorage'));
    }

    // The visible text of list pages tells us what is a favorite and what is on
    // the grocery list, which the ids alone do not.
    state.pages[where] = {
      url: location.href,
      title: document.title,
      text: (document.body?.innerText ?? '').slice(0, MAX_PAGE_TEXT),
    };

    save(state);
    const total = Object.keys(state.ids).length;
    console.log(
      `%cScanned ${where}: ${total - before} new, ${total} recipe ids total.`,
      'color: green; font-weight: bold'
    );
    console.log('Visit your other list pages and run __mise.scan() again, or run __mise.rescue() now.');
    return total;
  }

  // Links that might change something. A crawl only issues GETs, but a GET to
  // a sign out or delete route still does damage, so never follow these.
  const UNSAFE_LINK = /(sign[_-]?out|log[_-]?out|delete|destroy|remove|cancel|unsubscribe|reset|clear|checkout|purchase|subscri)/i;

  /** Same origin page links from a document, minus anything risky. */
  function linksFrom(html, base) {
    const doc = new DOMParser().parseFromString(html, 'text/html');
    const out = new Set();
    for (const anchor of doc.querySelectorAll('a[href]')) {
      let url;
      try {
        url = new URL(anchor.getAttribute('href'), base);
      } catch {
        continue;
      }
      if (url.origin !== location.origin) continue;
      if (UNSAFE_LINK.test(url.pathname + url.search)) continue;
      if (/\.(png|jpe?g|gif|webp|svg|pdf|css|js)$/i.test(url.pathname)) continue;
      out.add(url.pathname + url.search);
    }
    return [...out];
  }

  /**
   * Walks the site's own pages and harvests recipe ids from each one.
   *
   * my.mealime.com renders its lists into the HTML, so fetching a page with the
   * session cookie gives the same ids that visiting it would, without making
   * anyone click through and re-paste this script on every screen.
   */
  async function crawl({ maxPages = 60, concurrency = 4 } = {}) {
    const state = load();
    const queue = linksFrom(document.documentElement.innerHTML, location.href);
    const seen = new Set([location.pathname]);
    let visited = 0;

    const add = (id, source) => {
      const key = id.toLowerCase();
      state.ids[key] = state.ids[key] ?? { sources: [] };
      if (!state.ids[key].sources.includes(source)) state.ids[key].sources.push(source);
    };

    console.log(`Crawling up to ${maxPages} pages from ${queue.length} links`);
    while (queue.length > 0 && visited < maxPages) {
      const batch = [];
      while (batch.length < concurrency && queue.length > 0 && visited + batch.length < maxPages) {
        const next = queue.shift();
        if (seen.has(next)) continue;
        seen.add(next);
        batch.push(next);
      }
      if (batch.length === 0) break;

      await Promise.all(
        batch.map(async (pathAndQuery) => {
          try {
            const response = await fetch(pathAndQuery, { credentials: 'include' });
            if (!response.ok) return;
            const html = await response.text();
            const before = Object.keys(state.ids).length;
            for (const match of html.matchAll(UUID)) add(match[0], pathAndQuery);
            const found = Object.keys(state.ids).length - before;
            state.pages[pathAndQuery] = { url: pathAndQuery, title: '', text: '', crawled: true };
            if (found > 0) console.log(`  ${pathAndQuery}: ${found} new`);
            // Only follow deeper from pages that actually held recipes.
            if (found > 0) for (const link of linksFrom(html, location.origin + pathAndQuery)) {
              if (!seen.has(link)) queue.push(link);
            }
          } catch (error) {
            console.warn(`  ${pathAndQuery}: ${error.message}`);
          }
        })
      );
      visited += batch.length;
      save(state);
    }

    const total = Object.keys(state.ids).length;
    console.log(
      `%cCrawled ${visited} pages. ${total} recipe ids total.`,
      'color: green; font-weight: bold'
    );
    console.log('Run __mise.rescue() to download them.');
    return total;
  }

  /** Fetches the recipes, a few at a time, and downloads one JSON file. */
  async function rescue({ concurrency = 5 } = {}) {
    const state = load();
    const ids = Object.keys(state.ids);
    if (ids.length === 0) {
      console.warn('No recipe ids collected yet. Run __mise.scan() on a page that lists recipes.');
      return null;
    }

    console.log(`Fetching ${ids.length} recipes from ${CDN}`);
    const recipes = {};
    const failed = [];
    let done = 0;
    let cursor = 0;

    const worker = async () => {
      for (;;) {
        const index = cursor++;
        if (index >= ids.length) return;
        const id = ids[index];
        try {
          const response = await fetch(`${CDN}/${id}.json`, { credentials: 'omit' });
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          recipes[id] = await response.json();
        } catch (error) {
          failed.push({ id, error: String(error.message ?? error) });
        }
        done += 1;
        if (done % 20 === 0 || done === ids.length) console.log(`  ${done} of ${ids.length}`);
      }
    };
    await Promise.all(Array.from({ length: Math.min(concurrency, ids.length) }, worker));

    const dump = {
      format: 'mealime-rescue',
      version: 1,
      collectedAt: new Date().toISOString(),
      origin: location.origin,
      counts: { requested: ids.length, fetched: Object.keys(recipes).length, failed: failed.length },
      sources: state.ids,
      pages: state.pages,
      recipes,
      failed,
    };

    const blob = new Blob([JSON.stringify(dump, null, 2)], { type: 'application/json' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = 'mealime-rescue.json';
    document.body.appendChild(link);
    link.click();
    link.remove();

    console.log(
      `%cRescued ${dump.counts.fetched} recipes, ${failed.length} failed. Downloaded mealime-rescue.json`,
      'color: green; font-weight: bold'
    );
    if (failed.length) console.log('Failures:', failed);
    // Many ids on a page are not recipes, so some failures are normal and mean
    // the id pointed at something else.
    return dump;
  }

  window.__mise = {
    scan,
    crawl,
    rescue,
    status: () => {
      const state = load();
      console.log(`${Object.keys(state.ids).length} ids, pages scanned: ${Object.keys(state.pages).join(', ')}`);
      return state;
    },
    reset: () => {
      sessionStorage.removeItem(KEY);
      console.log('Cleared.');
    },
  };

  console.log(
    '%cMise rescue loaded.',
    'color: green; font-weight: bold',
    '\nRun __mise.crawl() to walk your pages automatically, then __mise.rescue() to download.',
    '\nIf you navigate, this script is gone and you paste it again. Collected ids survive.'
  );
})();
