// NYT Cooking Recipe Box export.
//
// Paste this whole file into the console on https://cooking.nytimes.com while
// signed in, then:
//
//   __nyt.probe()    say what this page looks like. Run it first.
//   __nyt.scan()     harvest recipes from the page you are on, scrolling it
//   __nyt.crawl()    find the folders and walk them all
//   __nyt.status()   how much has been collected so far
//   __nyt.rescue()   download nyt-recipe-box-raw.json
//
// Read only. It issues GETs to cooking.nytimes.com and nothing else. It never
// adds to, removes from, or marks anything in your Recipe Box.
//
// Unlike the Mealime rescue, the exact page structure here has not been seen by
// whoever wrote this, so the script tries several extraction strategies and
// tells you which one worked. If it finds nothing, run __nyt.probe() and send
// the output back rather than guessing.

(() => {
  const KEY = '__nytRecipeBox';
  const ORIGIN = 'https://cooking.nytimes.com';
  // cooking.nytimes.com/recipes/<numeric id>-<slug>. The id is the stable key
  // and is what the app dedupes on, per spec section 5.6a.
  const RECIPE_HREF = /\/recipes?\/(\d+)[-/]([a-z0-9-]*)/i;
  const RECIPE_ANYWHERE = /\/recipes?\/(\d+)-([a-z0-9-]+)/gi;
  const MAX_NEXT_DATA = 2_000_000;

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  const load = () => {
    try {
      return JSON.parse(sessionStorage.getItem(KEY)) ?? { recipes: {}, pages: {}, nextData: {} };
    } catch {
      return { recipes: {}, pages: {}, nextData: {} };
    }
  };
  const save = (state) => {
    try {
      sessionStorage.setItem(KEY, JSON.stringify(state));
    } catch (error) {
      console.warn('sessionStorage is full or blocked, collected data will not survive navigation.', error);
    }
  };

  /** The folder or list this page represents, as the user would name it. */
  function folderOfPage(doc = document, href = location.href) {
    const heading = doc.querySelector('h1, [class*="folderName" i], [data-testid*="folder" i]');
    const title = heading?.textContent?.trim();
    if (title && title.length < 80) return title;
    try {
      const url = new URL(href);
      const named = url.searchParams.get('folder') ?? url.searchParams.get('name');
      if (named) return decodeURIComponent(named);
      const last = url.pathname.split('/').filter(Boolean).pop();
      return last ? decodeURIComponent(last).replace(/-/g, ' ') : url.pathname;
    } catch {
      return href;
    }
  }

  /** Pulls the Next.js hydration payload, which is the most reliable source. */
  function nextDataOf(doc = document) {
    const tag = doc.getElementById('__NEXT_DATA__') ?? doc.querySelector('script#__NEXT_DATA__');
    if (!tag?.textContent) return null;
    try {
      return JSON.parse(tag.textContent);
    } catch {
      return null;
    }
  }

  /**
   * Finds recipe records in a hydration payload without assuming its shape:
   * any object carrying a recipe id plus a url or a name counts.
   */
  function fromJson(value, out = new Map(), depth = 0, seen = new Set()) {
    if (!value || typeof value !== 'object' || depth > 12 || seen.has(value)) return out;
    seen.add(value);
    if (Array.isArray(value)) {
      for (const entry of value) fromJson(entry, out, depth + 1, seen);
      return out;
    }
    const url = value.url ?? value.canonicalUrl ?? value.link ?? value.path;
    const idish = value.id ?? value.recipeId ?? value.recipe_id;
    const match = typeof url === 'string' ? url.match(RECIPE_HREF) : null;
    const id = match ? match[1] : /^\d+$/.test(String(idish ?? '')) && (value.title || value.name) ? String(idish) : null;
    if (id) {
      const existing = out.get(id) ?? { id };
      out.set(id, {
        ...existing,
        id,
        url: match ? new URL(match[0], ORIGIN).toString() : existing.url,
        slug: match ? match[2] : existing.slug,
        title: value.title ?? value.name ?? value.displayName ?? existing.title,
        author: value.author?.name ?? value.author ?? value.byline ?? existing.author,
        image: value.image?.url ?? value.imageUrl ?? value.image ?? existing.image,
        cookedAt: value.cookedAt ?? value.lastCookedAt ?? existing.cookedAt,
        via: 'nextData',
      });
    }
    for (const key of Object.keys(value)) fromJson(value[key], out, depth + 1, seen);
    return out;
  }

  /** Reads recipe links out of the rendered DOM. */
  function fromDom(doc = document) {
    const out = new Map();
    for (const anchor of doc.querySelectorAll('a[href*="/recipes/"], a[href*="/recipe/"]')) {
      const href = anchor.getAttribute('href') ?? '';
      const match = href.match(RECIPE_HREF);
      if (!match) continue;
      const id = match[1];
      const card = anchor.closest('article, li, div[class*="card" i]') ?? anchor;
      const title =
        anchor.getAttribute('aria-label')?.trim() ||
        card.querySelector('h1, h2, h3, h4, [class*="title" i]')?.textContent?.trim() ||
        anchor.textContent?.trim();
      out.set(id, {
        id,
        url: new URL(match[0], ORIGIN).toString(),
        slug: match[2] || undefined,
        title: title && title.length < 200 ? title : undefined,
        image: card.querySelector('img')?.getAttribute('src') ?? undefined,
        via: 'dom',
      });
    }
    return out;
  }

  /** Last resort: every recipe path anywhere in the markup. */
  function fromHtml(html) {
    const out = new Map();
    for (const match of html.matchAll(RECIPE_ANYWHERE)) {
      out.set(match[1], {
        id: match[1],
        url: `${ORIGIN}/recipes/${match[1]}-${match[2]}`,
        slug: match[2],
        via: 'html',
      });
    }
    return out;
  }

  /** Merges one page's findings into the collected state. */
  function absorb(state, found, { folder, pageUrl, cooked }) {
    let added = 0;
    for (const [id, record] of found) {
      const existing = state.recipes[id];
      if (!existing) added += 1;
      const merged = { ...existing, ...clean(record), id };
      merged.folders = [...new Set([...(existing?.folders ?? []), ...(folder ? [folder] : [])])];
      merged.foundOn = [...new Set([...(existing?.foundOn ?? []), pageUrl])];
      merged.cooked = Boolean(existing?.cooked || cooked || record.cookedAt);
      state.recipes[id] = merged;
    }
    return added;
  }

  /** Drops undefined values so a weaker source never erases a better one. */
  function clean(record) {
    return Object.fromEntries(Object.entries(record).filter(([, v]) => v !== undefined && v !== null && v !== ''));
  }

  const isCookedPage = (folder, url) => /cooked/i.test(`${folder} ${url}`);

  // Recently Viewed lists recipes the user merely opened. Importing those would
  // quietly fill the library with things they never chose to save, so it is
  // excluded everywhere, both from the crawl and from a manual scan.
  const NOT_SAVED = /recently[-_]?viewed|\/viewed\b/i;

  /** Scrolls to the bottom until the page stops growing, for lazy loaded lists. */
  async function autoScroll({ maxRounds = 40, pauseMs = 700 } = {}) {
    let previous = -1;
    for (let round = 0; round < maxRounds; round += 1) {
      const count = document.querySelectorAll('a[href*="/recipes/"]').length;
      if (count === previous) break;
      previous = count;
      window.scrollTo(0, document.body.scrollHeight);
      // Some lists paginate behind a button rather than on scroll.
      const more = [...document.querySelectorAll('button, a')].find((el) =>
        /load more|show more|see more|next/i.test(el.textContent ?? '')
      );
      if (more && more.offsetParent !== null) more.click();
      await sleep(pauseMs);
    }
    window.scrollTo(0, 0);
  }

  /** Says what this page offers, so nobody has to guess at its structure. */
  function probe() {
    const next = nextDataOf();
    const dom = fromDom();
    const json = next ? fromJson(next) : new Map();
    const html = fromHtml(document.documentElement.innerHTML);
    const folderLinks = [...document.querySelectorAll('a[href]')]
      .map((a) => a.getAttribute('href'))
      .filter((h) => h && /folder|recipe-box|collection|cooked/i.test(h));

    const report = {
      url: location.href,
      folderGuess: folderOfPage(),
      hasNextData: Boolean(next),
      counts: { fromNextData: json.size, fromDom: dom.size, fromHtml: html.size },
      folderLinks: [...new Set(folderLinks)].slice(0, 40),
      sampleFromDom: [...dom.values()].slice(0, 3),
    };
    console.log(report);
    if (report.counts.fromNextData + report.counts.fromDom + report.counts.fromHtml === 0) {
      console.warn('No recipes found on this page. Are you on your Recipe Box, and signed in?');
    }
    if (NOT_SAVED.test(location.pathname)) {
      console.warn('This page lists recipes you viewed rather than saved. It is excluded from collection.');
    }
    return report;
  }

  /** Harvests the page you are on. */
  async function scan({ scroll = true, folder = null, cooked = null, force = false } = {}) {
    if (!force && NOT_SAVED.test(location.pathname)) {
      console.warn(
        'This is Recently Viewed, which lists recipes you opened rather than saved. Skipping it. ' +
          'Run __nyt.scan({ force: true }) if you really want them.'
      );
      return Object.keys(load().recipes).length;
    }
    if (scroll) {
      console.log('Scrolling to load everything, this takes a moment');
      await autoScroll();
    }
    const state = load();
    const name = folder ?? folderOfPage();
    const next = nextDataOf();
    const found = new Map([
      ...fromHtml(document.documentElement.innerHTML),
      ...(next ? fromJson(next) : new Map()),
      ...fromDom(),
    ]);
    const added = absorb(state, found, {
      folder: name,
      pageUrl: location.href,
      cooked: cooked ?? isCookedPage(name, location.href),
    });
    state.pages[location.href] = { folder: name, found: found.size, at: new Date().toISOString() };
    if (next) {
      const text = JSON.stringify(next);
      if (text.length <= MAX_NEXT_DATA) state.nextData[location.href] = next;
      else state.pages[location.href].nextDataTooLarge = text.length;
    }
    save(state);
    const total = Object.keys(state.recipes).length;
    console.log(`%cScanned "${name}": ${found.size} on the page, ${added} new, ${total} total.`, 'color: green; font-weight: bold');
    return total;
  }

  /** Follows the Recipe Box folder links and scans each one. */
  async function crawl({ maxPages = 60 } = {}) {
    const state = load();
    const candidates = new Set();
    // Folder urls are numeric ids, so the only place the folder's real name
    // appears is the text of the link pointing at it.
    const folderNames = state.folderNames ?? {};

    const consider = (anchor, base) => {
      const href = anchor.getAttribute('href');
      if (!href) return;
      let url;
      try {
        url = new URL(href, base);
      } catch {
        return;
      }
      if (url.origin !== ORIGIN) return;
      if (!/folder|recipe-box|collection|cooked/i.test(url.pathname + url.search)) return;
      if (NOT_SAVED.test(url.pathname + url.search)) return;
      // A GET should be safe here, but never follow anything that reads like a
      // change. Losing a folder is worse than missing one page.
      if (/(sign[_-]?out|log[_-]?out|delete|remove|unsave|edit|new|create)/i.test(url.pathname + url.search)) return;
      const label = (anchor.textContent ?? '').trim();
      if (label && label.length < 80 && !folderNames[url.pathname]) folderNames[url.pathname] = label;
      candidates.add(url.toString());
    };

    for (const anchor of document.querySelectorAll('a[href]')) consider(anchor, location.href);

    console.log(`Found ${candidates.size} folder pages to fetch`);
    let visited = 0;
    // candidates grows while we walk it, which a Set iterator handles.
    for (const pageUrl of candidates) {
      if (visited >= maxPages) break;
      if (state.pages[pageUrl]?.fetched) continue;
      visited += 1;
      try {
        const response = await fetch(pageUrl, { credentials: 'include' });
        if (!response.ok) {
          console.warn(`  ${pageUrl}: HTTP ${response.status}`);
          continue;
        }
        const html = await response.text();
        const doc = new DOMParser().parseFromString(html, 'text/html');
        const next = nextDataOf(doc);
        const pathOnly = new URL(pageUrl).pathname;
        // A named link beats the url, which is often just a folder id.
        const folder = folderNames[pathOnly] ?? folderOfPage(doc, pageUrl);
        const found = new Map([...fromHtml(html), ...(next ? fromJson(next) : new Map()), ...fromDom(doc)]);
        const added = absorb(state, found, { folder, pageUrl, cooked: isCookedPage(folder, pageUrl) });
        state.pages[pageUrl] = { folder, found: found.size, at: new Date().toISOString(), fetched: true };
        console.log(`  ${folder}: ${found.size} found, ${added} new`);

        // The Recipe Box paginates with ?page=N, and later pages are only
        // linked from earlier ones, so keep following them.
        for (const anchor of doc.querySelectorAll('a[href]')) {
          const href = anchor.getAttribute('href') ?? '';
          if (!/[?&]page=\d+/.test(href)) continue;
          try {
            const next2 = new URL(href, pageUrl);
            if (next2.origin === ORIGIN && !NOT_SAVED.test(next2.pathname + next2.search)) {
              if (!folderNames[next2.pathname]) folderNames[next2.pathname] = folder;
              candidates.add(next2.toString());
            }
          } catch {
            // Skip a href we cannot parse.
          }
        }
      } catch (error) {
        console.warn(`  ${pageUrl}: ${error.message}`);
      }
      await sleep(400);
    }
    state.folderNames = folderNames;
    save(state);
    const total = Object.keys(state.recipes).length;
    console.log(`%cCrawled ${visited} pages. ${total} recipes total.`, 'color: green; font-weight: bold');
    console.log('A fetched folder page may not include lazily loaded rows. Open any folder that looks short and run __nyt.scan().');
    return total;
  }

  function status() {
    const state = load();
    const recipes = Object.values(state.recipes);
    const byFolder = {};
    for (const recipe of recipes) {
      for (const folder of recipe.folders ?? ['(none)']) byFolder[folder] = (byFolder[folder] ?? 0) + 1;
    }
    console.log(`${recipes.length} recipes, ${recipes.filter((r) => r.cooked).length} marked cooked`);
    console.log('By folder:', byFolder);
    console.log('Pages scanned:', Object.keys(state.pages).length);
    return { total: recipes.length, byFolder };
  }

  function rescue() {
    const state = load();
    const recipes = Object.values(state.recipes);
    if (recipes.length === 0) {
      console.warn('Nothing collected. Run __nyt.probe() and send the output back.');
      return null;
    }
    const dump = {
      format: 'nyt-recipe-box-raw',
      version: 1,
      collectedAt: new Date().toISOString(),
      origin: location.origin,
      counts: {
        recipes: recipes.length,
        cooked: recipes.filter((r) => r.cooked).length,
        pages: Object.keys(state.pages).length,
        withTitle: recipes.filter((r) => r.title).length,
      },
      recipes,
      pages: state.pages,
      nextData: state.nextData,
    };
    const blob = new Blob([JSON.stringify(dump, null, 2)], { type: 'application/json' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'nyt-recipe-box-raw.json';
    document.body.appendChild(a);
    a.click();
    a.remove();
    console.log(`%cDownloaded nyt-recipe-box-raw.json with ${recipes.length} recipes.`, 'color: green; font-weight: bold');
    console.log('Next: node src/cli.mjs convert --in ~/Downloads/nyt-recipe-box-raw.json');
    return dump.counts;
  }

  window.__nyt = {
    probe,
    scan,
    crawl,
    status,
    rescue,
    reset: () => sessionStorage.removeItem(KEY),
    // Exposed so the extraction logic can be tested without a browser. The
    // page structure here has never been seen by whoever wrote this, so these
    // are the parts most likely to be wrong and most worth covering.
    __internals: { fromJson, fromHtml, fromDom, absorb, folderOfPage, isCookedPage, nextDataOf, clean },
  };
  console.log(
    '%cNYT Recipe Box export loaded.',
    'color: green; font-weight: bold',
    '\nStart with __nyt.probe(), then __nyt.scan(), then __nyt.crawl(), then __nyt.rescue().'
  );
})();
