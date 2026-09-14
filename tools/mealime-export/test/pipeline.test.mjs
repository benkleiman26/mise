// End to end test for the normalize step, over a synthetic raw export.
//
// The unit tests cover the mapping functions. This one covers what they do not:
// reading the raw layout off disk, writing every output file, and getting the
// provenance split right in a real run.

import { strict as assert } from 'node:assert';
import { test, describe, before, after } from 'node:test';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { runNormalize } from '../src/normalize.mjs';

// A recipe the user imported themselves: it has a source url and sits in their
// own list, so its text is theirs and travels in full.
const USER_RECIPE = {
  recipe: {
    uuid: 'abc123',
    name: 'Sheet Pan Salmon',
    serving_count: 4,
    cooking_minutes: 25,
    source_url: 'https://blog.test/salmon',
    image_url: 'https://img.test/salmon.jpg',
    cookwares: [{ name: 'sheet pan' }],
    line_items: [
      { quantity: '1 1/2 lb', ingredient_name: 'salmon fillet' },
      { quantity: '2 tbsp', ingredient_name: 'olive oil' },
    ],
    instructions: [
      { position: 1, primary_message: 'Heat the oven to 425.', secondary_message: '' },
      { position: 2, primary_message: 'Roast until flaky.', secondary_message: '1 1/2 lb salmon fillet' },
    ],
    nutrition: { energy: 410, protein: 34 },
  },
};

// A recipe Mealime wrote: favorited, no source url. Reference only.
const MEALIME_RECIPE = {
  uuid: 'xyz789',
  name: 'Mealime Chicken Bowls',
  serving_count: 2,
  cooking_minutes: 30,
  image_url: 'https://img.test/bowls.jpg',
  line_items: [{ quantity: '1 lb', ingredient_name: 'chicken thighs' }],
  instructions: [{ position: 1, primary_message: 'Cook the chicken.' }],
};

async function writeJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(value, null, 2), 'utf8');
}

async function buildRawExport(root) {
  const raw = path.join(root, 'raw');
  await writeJson(path.join(raw, 'recipes', 'abc123.json'), USER_RECIPE);
  await writeJson(path.join(raw, 'recipes', 'xyz789.json'), MEALIME_RECIPE);
  await writeJson(path.join(raw, '_recipe_index.json'), [
    { id: 'abc123', roles: ['userRecipes'], summary: {} },
    { id: 'xyz789', roles: ['favorites'], summary: {} },
  ]);
  await writeJson(path.join(raw, 'collections', 'favorites.page-0.json'), {
    data: [{ uuid: 'xyz789', name: 'Mealime Chicken Bowls' }],
  });
  await writeJson(path.join(raw, 'collections', 'groceryLists.page-0.json'), {
    grocery_list: {
      items: [
        { name: 'salmon fillet', recipe_ids: ['abc123'] },
        { name: 'Dish soap', is_manual: true, quantity: '1' },
        { name: 'Seltzer', manual: true, aisle: 'Beverages' },
      ],
    },
  });
  await writeJson(path.join(raw, 'preferences.json'), {
    menu_type: 'Pescetarian',
    allergies: [],
    disliked_ingredients: ['olives'],
    meal_size: 4,
    units: 'us',
  });
}

describe('normalize, end to end', () => {
  let dir;
  let bundle;

  before(async () => {
    dir = await mkdtemp(path.join(tmpdir(), 'mealime-export-'));
    await buildRawExport(dir);
    await runNormalize({ outDir: dir, log: () => {} });
    bundle = JSON.parse(await readFile(path.join(dir, 'mealime-export.json'), 'utf8'));
  });

  after(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  test('writes every output file the app and the owner need', async () => {
    for (const file of ['mealime-export.json', 'favorites.json', 'manual_items.json', '_normalize_report.json']) {
      await readFile(path.join(dir, file), 'utf8');
    }
    const recipe = JSON.parse(await readFile(path.join(dir, 'recipes', 'abc123.json'), 'utf8'));
    assert.equal(recipe.name, 'Sheet Pan Salmon');
  });

  test('carries the user\'s own recipe in full', () => {
    assert.equal(bundle.recipes.length, 1);
    const [recipe] = bundle.recipes;
    assert.equal(recipe.name, 'Sheet Pan Salmon');
    assert.equal(recipe.provenance, 'userImported');
    assert.equal(recipe.line_items.length, 2);
    assert.equal(recipe.instructions.length, 2);
    assert.deepEqual(recipe.cookwares, ['sheet pan']);
    assert.equal(recipe.nutrition.energy, 410);
  });

  test('keeps only a reference for the recipe Mealime wrote', () => {
    assert.equal(bundle.withheld.length, 1);
    const [withheld] = bundle.withheld;
    assert.equal(withheld.name, 'Mealime Chicken Bowls');
    assert.equal(withheld.content_withheld, true);
    assert.equal(withheld.image, 'https://img.test/bowls.jpg');
    assert.equal(withheld.line_items, undefined, 'withheld recipes must not carry ingredients');
    assert.equal(withheld.instructions, undefined, 'withheld recipes must not carry steps');
  });

  test('a withheld favorite is still listed once, as a reference', () => {
    assert.equal(bundle.favorites.length, 1);
    assert.equal(bundle.favorites[0].mealime_id, 'xyz789');
  });

  test('brings the eating preferences across', () => {
    assert.equal(bundle.preferences.menuType, 'pescetarian');
    assert.deepEqual(bundle.preferences.dislikedIngredients, ['olives']);
    assert.equal(bundle.preferences.defaultServings, 4);
  });

  test('keeps hand added grocery items and drops recipe driven ones', () => {
    assert.deepEqual(bundle.manualItems.map((i) => i.name), ['Dish soap', 'Seltzer']);
  });

  test('a full private copy keeps everything instead', async () => {
    await runNormalize({ outDir: dir, includeMealimeContent: true, log: () => {} });
    const full = JSON.parse(await readFile(path.join(dir, 'mealime-export.json'), 'utf8'));
    assert.equal(full.recipes.length, 2);
    assert.equal(full.withheld.length, 0);
    assert.equal(full.source.includesMealimeContent, true);
  });
});
