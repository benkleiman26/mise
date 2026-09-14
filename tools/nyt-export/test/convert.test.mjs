import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { buildRecipeBox, folderToTag, normalizeRecipe, reviewWarnings, runConvert } from '../src/convert.mjs';

describe('folderToTag', () => {
  test('turns a folder name into a flat lowercase tag', () => {
    assert.equal(folderToTag('Easy Kid-Friendly Recipes'), 'kid friendly');
    assert.equal(folderToTag('Weeknight Dinners'), 'weeknight dinners');
  });

  test('refuses folders that describe status rather than topic', () => {
    assert.equal(folderToTag('Cooked Recipes'), null);
    assert.equal(folderToTag('Recipes'), null);
    assert.equal(folderToTag('Recipe Box'), null);
    assert.equal(folderToTag('Saved'), null);
  });

  test('refuses anything that reduces to nothing useful', () => {
    assert.equal(folderToTag(''), null);
    assert.equal(folderToTag('   '), null);
    assert.equal(folderToTag('!!'), null);
    assert.equal(folderToTag(null), null);
  });
});

describe('normalizeRecipe', () => {
  test('keeps a well formed record', () => {
    const out = normalizeRecipe({
      id: '1020000',
      url: 'https://cooking.nytimes.com/recipes/1020000-sheet-pan-salmon',
      title: 'Sheet-Pan Salmon',
      author: 'Melissa Clark',
      folders: ['Easy Kid-Friendly Recipes'],
      cooked: true,
    });
    assert.equal(out.id, '1020000');
    assert.equal(out.title, 'Sheet-Pan Salmon');
    assert.deepEqual(out.tags, ['kid friendly']);
    assert.equal(out.cooked, true);
  });

  test('rebuilds a missing or malformed url from the id', () => {
    assert.equal(
      normalizeRecipe({ id: '123', slug: 'good-soup' }).url,
      'https://cooking.nytimes.com/recipes/123-good-soup'
    );
    assert.equal(normalizeRecipe({ id: '123' }).url, 'https://cooking.nytimes.com/recipes/123');
    assert.equal(
      normalizeRecipe({ id: '123', url: 'https://evil.test/recipes/123-x' }).url,
      'https://cooking.nytimes.com/recipes/123'
    );
  });

  test('rejects anything that is not a recipe, since the harvest over collects', () => {
    assert.equal(normalizeRecipe({ id: 'not-a-number' }), null);
    assert.equal(normalizeRecipe({ url: 'https://cooking.nytimes.com/about' }), null);
    assert.equal(normalizeRecipe(null), null);
    assert.equal(normalizeRecipe({}), null);
  });

  test('records whether a title was actually harvested', () => {
    assert.equal(normalizeRecipe({ id: '1' }).titleFromHarvest, false);
    assert.equal(normalizeRecipe({ id: '1', title: 'X' }).titleFromHarvest, true);
  });
});

describe('buildRecipeBox', () => {
  const dump = {
    format: 'nyt-recipe-box-raw',
    collectedAt: '2026-09-14T00:00:00Z',
    pages: { a: {}, b: {} },
    recipes: [
      { id: '200', url: 'https://cooking.nytimes.com/recipes/200-tacos', title: 'Tacos', folders: ['Easy Kid-Friendly Recipes'] },
      { id: '100', url: 'https://cooking.nytimes.com/recipes/100-soup', title: 'Soup', folders: ['Recipes'], cooked: true },
      { id: '200', url: 'https://cooking.nytimes.com/recipes/200-tacos', folders: ['Cooked Recipes'], cooked: true },
      { id: 'junk', url: 'https://cooking.nytimes.com/about' },
    ],
  };

  test('merges a recipe seen in two folders instead of duplicating it', () => {
    const box = buildRecipeBox(dump);
    const tacos = box.recipes.find((r) => r.id === '200');
    assert.equal(box.recipes.filter((r) => r.id === '200').length, 1);
    assert.deepEqual(tacos.folders.sort(), ['Cooked Recipes', 'Easy Kid-Friendly Recipes']);
    assert.equal(tacos.cooked, true, 'cooked from the second sighting should stick');
    assert.equal(tacos.title, 'Tacos', 'the title from the first sighting should survive');
    assert.deepEqual(tacos.tags, ['kid friendly'], 'a status folder should not become a tag');
  });

  test('drops non recipes and says how many', () => {
    const box = buildRecipeBox(dump);
    assert.equal(box.counts.recipes, 2);
    assert.equal(box.counts.rejected, 1);
  });

  test('sorts by id and counts folders', () => {
    const box = buildRecipeBox(dump);
    assert.deepEqual(box.recipes.map((r) => r.id), ['100', '200']);
    assert.equal(box.counts.cooked, 2);
    const kidFriendly = box.folders.find((f) => f.name === 'Easy Kid-Friendly Recipes');
    assert.equal(kidFriendly.count, 1);
    assert.equal(kidFriendly.tag, 'kid friendly');
  });

  test('declares a stable format and version', () => {
    const box = buildRecipeBox({ recipes: [] });
    assert.equal(box.format, 'nyt-recipe-box');
    assert.equal(box.version, 1);
  });

  test('accepts recipes as a keyed object as well as an array', () => {
    const box = buildRecipeBox({ recipes: { 100: { id: '100' }, 200: { id: '200' } } });
    assert.equal(box.counts.recipes, 2);
  });
});

describe('reviewWarnings', () => {
  test('warns when the harvest is well short of what is expected', () => {
    const box = buildRecipeBox({ recipes: [{ id: '1', title: 'x', cooked: true, folders: ['A', 'B'] }] });
    assert.match(reviewWarnings(box, { expected: 163 }).join(' '), /about 163 were expected/);
  });

  test('warns when nothing is marked cooked', () => {
    const recipes = Array.from({ length: 163 }, (_, i) => ({ id: String(i + 1), title: 't', folders: ['A', 'B'] }));
    assert.match(reviewWarnings(buildRecipeBox({ recipes })).join(' '), /Nothing is marked cooked/);
  });

  test('warns when most records have no title', () => {
    const recipes = Array.from({ length: 163 }, (_, i) => ({ id: String(i + 1), cooked: true, folders: ['A', 'B'] }));
    assert.match(reviewWarnings(buildRecipeBox({ recipes })).join(' '), /came from raw link matching/);
  });

  test('stays quiet on a healthy export', () => {
    const recipes = Array.from({ length: 163 }, (_, i) => ({
      id: String(i + 1), title: 't', cooked: i < 20, folders: ['Easy Kid-Friendly Recipes', 'Weeknight'],
    }));
    assert.deepEqual(reviewWarnings(buildRecipeBox({ recipes })), []);
  });
});

describe('runConvert', () => {
  test('writes the file the app will read', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'nyt-'));
    const inFile = path.join(dir, 'raw.json');
    const outFile = path.join(dir, 'nyt', 'nyt_recipe_box.json');
    await writeFile(
      inFile,
      JSON.stringify({
        format: 'nyt-recipe-box-raw',
        recipes: [{ id: '1020000', url: 'https://cooking.nytimes.com/recipes/1020000-x', title: 'X', folders: ['Easy Kid-Friendly Recipes'] }],
      })
    );
    const box = await runConvert({ inFile, outFile, log: () => {} });
    const written = JSON.parse(await readFile(outFile, 'utf8'));
    assert.equal(written.recipes.length, 1);
    assert.deepEqual(written.recipes[0].tags, ['kid friendly']);
    assert.equal(box.format, 'nyt-recipe-box');
    await rm(dir, { recursive: true, force: true });
  });
});
