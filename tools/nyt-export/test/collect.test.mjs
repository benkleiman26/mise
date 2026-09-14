// Tests for the browser collector, driven against stubbed globals.
//
// The Recipe Box page structure has not been observed directly, so these cover
// the three extraction strategies independently. If NYT's markup differs from
// what is assumed, at least one strategy should still fire, and these tests say
// which is which.

import { strict as assert } from 'node:assert';
import { test, describe, before } from 'node:test';
import { readFileSync } from 'node:fs';

/** Enough of a DOM for the collector to run against. */
function stubDom({ html = '', anchors = [], nextData = null, heading = null } = {}) {
  const makeAnchor = ({ href, title, image, cardTitle }) => ({
    getAttribute: (name) => (name === 'href' ? href : name === 'aria-label' ? title ?? null : name === 'src' ? image ?? null : null),
    textContent: title ?? '',
    closest: () => ({
      querySelector: (selector) => {
        if (selector.includes('img')) return image ? { getAttribute: () => image } : null;
        return cardTitle ? { textContent: cardTitle } : null;
      },
    }),
  });
  return {
    title: 'Recipe Box',
    documentElement: { innerHTML: html },
    body: { innerText: '', scrollHeight: 100, appendChild() {} },
    getElementById: (id) => (id === '__NEXT_DATA__' && nextData ? { textContent: JSON.stringify(nextData) } : null),
    querySelector: (selector) => {
      if (/h1/.test(selector) && heading) return { textContent: heading };
      if (/__NEXT_DATA__/.test(selector) && nextData) return { textContent: JSON.stringify(nextData) };
      return null;
    },
    querySelectorAll: (selector) => {
      if (selector.includes('/recipes/')) return anchors.map(makeAnchor);
      return [];
    },
    createElement: () => ({ click() {}, remove() {}, set href(v) {}, set download(v) { globalThis.__name = v; } }),
  };
}

let internals;

before(() => {
  const store = new Map();
  globalThis.sessionStorage = {
    getItem: (k) => store.get(k) ?? null,
    setItem: (k, v) => store.set(k, v),
    removeItem: (k) => store.delete(k),
  };
  globalThis.location = { origin: 'https://cooking.nytimes.com', href: 'https://cooking.nytimes.com/recipe-box', pathname: '/recipe-box' };
  globalThis.document = stubDom();
  globalThis.window = globalThis;
  globalThis.Blob = class { constructor(parts) { globalThis.__blob = parts[0]; } };
  globalThis.URL.createObjectURL = () => 'blob:x';
  globalThis.DOMParser = class { parseFromString() { return stubDom(); } };
  const quiet = console.log;
  console.log = () => {};
  eval(readFileSync(new URL('../browser/collect.js', import.meta.url), 'utf8'));
  console.log = quiet;
  internals = globalThis.__nyt.__internals;
});

describe('fromHtml, the last resort strategy', () => {
  test('finds every recipe path in raw markup', () => {
    const found = internals.fromHtml(`
      <a href="/recipes/1020000-sheet-pan-salmon">x</a>
      <div data-url="https://cooking.nytimes.com/recipes/24242-good-soup"></div>
      <a href="/about">not a recipe</a>
    `);
    assert.deepEqual([...found.keys()].sort(), ['1020000', '24242']);
    assert.equal(found.get('1020000').url, 'https://cooking.nytimes.com/recipes/1020000-sheet-pan-salmon');
  });

  test('finds nothing in markup with no recipes', () => {
    assert.equal(internals.fromHtml('<p>nothing here</p>').size, 0);
  });
});

describe('fromJson, the hydration strategy', () => {
  test('pulls recipes out of a nested payload without assuming its shape', () => {
    const found = internals.fromJson({
      props: {
        pageProps: {
          folder: { name: 'Easy Kid-Friendly Recipes' },
          recipes: [
            { id: 1020000, title: 'Sheet-Pan Salmon', url: '/recipes/1020000-sheet-pan-salmon', author: { name: 'Melissa Clark' } },
            { id: 24242, name: 'Good Soup', url: 'https://cooking.nytimes.com/recipes/24242-good-soup' },
          ],
        },
      },
    });
    assert.equal(found.size, 2);
    assert.equal(found.get('1020000').title, 'Sheet-Pan Salmon');
    assert.equal(found.get('1020000').author, 'Melissa Clark');
    assert.equal(found.get('24242').title, 'Good Soup');
  });

  test('ignores objects that merely have an id', () => {
    assert.equal(internals.fromJson({ tracking: { id: 99 }, config: { id: 12, enabled: true } }).size, 0);
  });

  test('survives cycles and deep nesting', () => {
    const cyclic = { a: {} };
    cyclic.a.back = cyclic;
    assert.doesNotThrow(() => internals.fromJson(cyclic));
  });
});

describe('fromDom, the rendered page strategy', () => {
  test('reads id, title and image off recipe cards', () => {
    globalThis.document = stubDom({
      anchors: [{ href: '/recipes/1020000-sheet-pan-salmon', title: 'Sheet-Pan Salmon', image: 'https://img.test/a.jpg' }],
    });
    const found = internals.fromDom(globalThis.document);
    assert.equal(found.size, 1);
    assert.equal(found.get('1020000').title, 'Sheet-Pan Salmon');
    assert.equal(found.get('1020000').image, 'https://img.test/a.jpg');
  });
});

describe('absorb', () => {
  test('accumulates folders and never downgrades a field it already has', () => {
    const state = { recipes: {}, pages: {}, nextData: {} };
    internals.absorb(state, new Map([['1', { id: '1', title: 'Tacos', url: 'u' }]]), {
      folder: 'Easy Kid-Friendly Recipes', pageUrl: '/a', cooked: false,
    });
    internals.absorb(state, new Map([['1', { id: '1' }]]), { folder: 'Cooked Recipes', pageUrl: '/b', cooked: true });

    const recipe = state.recipes['1'];
    assert.equal(recipe.title, 'Tacos', 'a later thinner sighting must not erase the title');
    assert.deepEqual(recipe.folders.sort(), ['Cooked Recipes', 'Easy Kid-Friendly Recipes']);
    assert.deepEqual(recipe.foundOn.sort(), ['/a', '/b']);
    assert.equal(recipe.cooked, true);
  });

  test('reports how many were new', () => {
    const state = { recipes: {}, pages: {}, nextData: {} };
    const found = new Map([['1', { id: '1' }], ['2', { id: '2' }]]);
    assert.equal(internals.absorb(state, found, { folder: 'A', pageUrl: '/a' }), 2);
    assert.equal(internals.absorb(state, found, { folder: 'A', pageUrl: '/a' }), 0);
  });
});

describe('folder naming and cooked detection', () => {
  test('prefers the page heading, then the url', () => {
    assert.equal(internals.folderOfPage(stubDom({ heading: 'Easy Kid-Friendly Recipes' }), 'https://x.test/y'), 'Easy Kid-Friendly Recipes');
    assert.equal(internals.folderOfPage(stubDom(), 'https://cooking.nytimes.com/recipe-box?folder=Weeknight%20Wins'), 'Weeknight Wins');
    assert.equal(internals.folderOfPage(stubDom(), 'https://cooking.nytimes.com/recipe-box/cooked-recipes'), 'cooked recipes');
  });

  test('spots the cooked list from either the name or the url', () => {
    assert.equal(internals.isCookedPage('Cooked Recipes', '/x'), true);
    assert.equal(internals.isCookedPage('Recipes', '/recipe-box/cooked'), true);
    assert.equal(internals.isCookedPage('Recipes', '/recipe-box'), false);
  });
});

describe('rescue', () => {
  test('refuses to download an empty collection rather than writing a useless file', () => {
    globalThis.__nyt.reset();
    assert.equal(globalThis.__nyt.rescue(), null);
  });

  test('downloads what was collected', async () => {
    globalThis.__nyt.reset();
    globalThis.document = stubDom({ html: '<a href="/recipes/1020000-salmon">x</a>', heading: 'Easy Kid-Friendly Recipes' });
    await globalThis.__nyt.scan({ scroll: false });
    const counts = globalThis.__nyt.rescue();
    assert.equal(counts.recipes, 1);
    assert.equal(globalThis.__name, 'nyt-recipe-box-raw.json');
    const dump = JSON.parse(globalThis.__blob);
    assert.equal(dump.format, 'nyt-recipe-box-raw');
    assert.deepEqual(dump.recipes[0].folders, ['Easy Kid-Friendly Recipes']);
  });
});

describe('Recently Viewed is never collected', () => {
  test('scan refuses on a recently viewed page unless forced', async () => {
    globalThis.__nyt.reset();
    const saved = globalThis.location;
    globalThis.location = {
      origin: 'https://cooking.nytimes.com',
      href: 'https://cooking.nytimes.com/recipe-box/recently-viewed',
      pathname: '/recipe-box/recently-viewed',
    };
    globalThis.document = stubDom({ html: '<a href="/recipes/999-viewed-not-saved">x</a>' });

    const afterRefusal = await globalThis.__nyt.scan({ scroll: false });
    assert.equal(afterRefusal, 0, 'a page of merely viewed recipes must not be collected');

    const afterForce = await globalThis.__nyt.scan({ scroll: false, force: true });
    assert.equal(afterForce, 1, 'force should still allow it');

    globalThis.location = saved;
    globalThis.__nyt.reset();
  });
});
