import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { readFileSync } from 'node:fs';

import { canonicalUrl, decodeEntities, looksLikeRecipe, nytRecipeId, parseBookmarks } from '../src/bookmarks.mjs';
import { buildInventory } from '../src/inventory.mjs';

const HTML = readFileSync(new URL('./fixtures/bookmarks.html', import.meta.url), 'utf8');

describe('parseBookmarks', () => {
  const { bookmarks, folders } = parseBookmarks(HTML);

  test('finds every http link and skips the rest', () => {
    assert.equal(bookmarks.length, 9, 'the javascript: bookmarklet should be skipped');
    assert.ok(!bookmarks.some((b) => b.url.startsWith('javascript:')));
  });

  test('tracks the folder each bookmark sits in, including nesting', () => {
    const soup = bookmarks.find((b) => b.url.includes('24242'));
    assert.equal(soup.folder, 'Bookmarks bar/Recipes to try');
    const salmon = bookmarks.find((b) => b.url.includes('1020000'));
    assert.equal(salmon.folder, 'Bookmarks bar');
    const beans = bookmarks.find((b) => b.url.includes('bonappetit'));
    assert.equal(beans.folder, 'Other bookmarks', 'the stack must unwind when a folder closes');
  });

  test('lists the folders it saw', () => {
    assert.deepEqual(folders.sort(), ['Bookmarks bar', 'Bookmarks bar/Recipes to try', 'Other bookmarks']);
  });

  test('decodes entities in titles and urls', () => {
    assert.equal(bookmarks.find((b) => b.url.includes('24242')).title, 'Good Soup & Bread');
    assert.ok(bookmarks.find((b) => b.url.includes('smittenkitchen') && b.url.includes('utm_medium')));
  });

  test('reads the added date', () => {
    assert.match(bookmarks[0].addedAt, /^2025-/);
  });

  test('returns nothing rather than throwing on junk input', () => {
    assert.deepEqual(parseBookmarks('').bookmarks, []);
    assert.deepEqual(parseBookmarks(null).bookmarks, []);
    assert.deepEqual(parseBookmarks('<p>not bookmarks</p>').bookmarks, []);
  });
});

describe('decodeEntities', () => {
  test('handles named and numeric entities', () => {
    assert.equal(decodeEntities('a &amp; b &lt;c&gt; &quot;d&quot; &#39;e&#39;'), 'a & b <c> "d" \'e\'');
  });
});

describe('canonicalUrl', () => {
  test('collapses the differences that create false duplicates', () => {
    assert.equal(
      canonicalUrl('https://smittenkitchen.com/2024/03/lemon-pasta/?utm_source=x&utm_medium=email'),
      canonicalUrl('https://smittenkitchen.com/2024/03/lemon-pasta#notes')
    );
    assert.equal(canonicalUrl('https://www.example.com/a/'), 'https://example.com/a');
  });

  test('keeps parameters that identify the page', () => {
    assert.match(canonicalUrl('https://example.com/r?id=7'), /id=7/);
  });
});

describe('nytRecipeId', () => {
  test('reads the numeric id the app dedupes on', () => {
    assert.equal(nytRecipeId('https://cooking.nytimes.com/recipes/1020000-sheet-pan-salmon'), '1020000');
    assert.equal(nytRecipeId('https://www.cooking.nytimes.com/recipe/24242'), '24242');
    assert.equal(nytRecipeId('https://cooking.nytimes.com/topics/dinner'), null);
    assert.equal(nytRecipeId('not a url'), null);
  });
});

describe('looksLikeRecipe', () => {
  test('says no to search, social and code', () => {
    assert.equal(looksLikeRecipe({ url: 'https://www.google.com/search?q=dinner' }), false);
    assert.equal(looksLikeRecipe({ url: 'https://www.youtube.com/watch?v=x' }), false);
    assert.equal(looksLikeRecipe({ url: 'https://github.com/a/b' }), false);
  });

  test('says yes to recipe hosts and paths', () => {
    assert.equal(looksLikeRecipe({ url: 'https://cooking.nytimes.com/recipes/1-x' }), true);
    assert.equal(looksLikeRecipe({ url: 'https://www.seriouseats.com/the-best-chili-recipe' }), true);
    assert.equal(looksLikeRecipe({ url: 'https://example.com/x', title: 'Roast Chicken Recipe' }), true);
  });

  test('gives an unknown host with a real path the benefit of the doubt', () => {
    assert.equal(looksLikeRecipe({ url: 'https://someblog.test/2024/03/thing' }), true);
    assert.equal(looksLikeRecipe({ url: 'https://someblog.test/' }), false);
  });
});

describe('buildInventory', () => {
  const inventory = buildInventory({ html: HTML, knownNytIds: new Set(['1020000']) });

  test('collapses duplicate urls and keeps both folders', () => {
    assert.equal(inventory.counts.duplicates, 1, 'the two lemon pasta bookmarks are one url');
    assert.equal(inventory.counts.unique, 8);
  });

  test('marks what is already in the Recipe Box so it is not imported twice', () => {
    assert.equal(inventory.counts.nytRecipes, 2);
    assert.equal(inventory.counts.alreadyInRecipeBox, 1);
    const salmon = inventory.entries.find((e) => e.nytRecipeId === '1020000');
    assert.equal(salmon.alreadyInRecipeBox, true);
  });

  test('separates recipes from everything else', () => {
    assert.equal(inventory.counts.notRecipes, 3, 'google, youtube and github');
    assert.equal(inventory.counts.toImport, inventory.counts.likelyRecipes - 1);
  });

  test('counts hosts, most common first', () => {
    assert.equal(inventory.hosts[0].count >= inventory.hosts.at(-1).count, true);
    assert.ok(inventory.hosts.some((h) => h.host === 'cooking.nytimes.com'));
  });

  test('can be narrowed to one bookmarks folder', () => {
    const narrowed = buildInventory({ html: HTML, folderFilter: 'Recipes to try' });
    assert.equal(narrowed.counts.selected, 6);
    assert.ok(narrowed.entries.every((e) => e.folders.some((f) => f.includes('Recipes to try'))));
  });

  test('declares a stable format and version', () => {
    assert.equal(inventory.format, 'bookmarks-inventory');
    assert.equal(inventory.version, 1);
  });
});
