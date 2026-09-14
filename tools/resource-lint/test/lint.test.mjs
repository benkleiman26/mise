import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { readFileSync } from 'node:fs';

import { AISLES, UNITS, lintCanonicalItems, lintSeedRecipes } from '../src/lint.mjs';

const read = (name) => JSON.parse(readFileSync(new URL(`../../../Mise/Resources/${name}`, import.meta.url), 'utf8'));

const GOOD_CANONICAL = {
  format: 'canonical-items',
  version: 1,
  aisleOrder: AISLES,
  items: [
    { name: 'olive oil', aliases: ['extra virgin olive oil'], aisle: 'oilsAndCondiments', defaultUnit: 'floz', isStaple: true },
    { name: 'salmon', aliases: ['salmon fillet'], aisle: 'seafood', defaultUnit: 'lb' },
  ],
};

describe('lintCanonicalItems', () => {
  test('passes a good file', () => {
    assert.deepEqual(lintCanonicalItems(GOOD_CANONICAL), []);
  });

  test('catches an alias claimed by two items, which would misfile groceries', () => {
    const problems = lintCanonicalItems({
      ...GOOD_CANONICAL,
      items: [
        { name: 'butter', aliases: ['unsalted butter'], aisle: 'dairyAndEggs' },
        { name: 'ghee', aliases: ['unsalted butter'], aisle: 'dairyAndEggs' },
      ],
    });
    assert.equal(problems.length, 1);
    assert.match(problems[0], /claimed twice/);
  });

  test('catches an alias that collides with another item name', () => {
    const problems = lintCanonicalItems({
      ...GOOD_CANONICAL,
      items: [
        { name: 'black pepper', aliases: ['pepper'], aisle: 'bakingAndSpices' },
        { name: 'pepper', aisle: 'produce' },
      ],
    });
    assert.match(problems.join(' '), /claimed twice/);
  });

  test('catches duplicate names regardless of case', () => {
    const problems = lintCanonicalItems({
      ...GOOD_CANONICAL,
      items: [{ name: 'salt', aisle: 'bakingAndSpices' }, { name: 'salt', aisle: 'bakingAndSpices' }],
    });
    assert.match(problems.join(' '), /claimed twice/);
  });

  test('rejects unknown aisles and units', () => {
    const problems = lintCanonicalItems({
      ...GOOD_CANONICAL,
      items: [{ name: 'x', aisle: 'condiments', defaultUnit: 'handful' }],
    });
    assert.match(problems.join(' '), /unknown aisle/);
    assert.match(problems.join(' '), /unknown defaultUnit/);
  });

  test('requires every aisle to appear in the store walk order', () => {
    const problems = lintCanonicalItems({ ...GOOD_CANONICAL, aisleOrder: ['produce'] });
    assert.match(problems.join(' '), /aisleOrder is missing/);
  });

  test('insists on lowercase, trimmed names', () => {
    const problems = lintCanonicalItems({ ...GOOD_CANONICAL, items: [{ name: ' Olive Oil', aisle: 'produce' }] });
    assert.match(problems.join(' '), /whitespace/);
    assert.match(problems.join(' '), /lowercase/);
  });
});

describe('lintSeedRecipes', () => {
  const GOOD_SEED = {
    format: 'seed-recipes',
    version: 1,
    recipes: [
      {
        id: 'seed-1',
        title: 'Quick Salmon',
        baseServings: 4,
        totalMinutes: 25,
        ingredients: [
          { name: 'salmon fillet', canonicalItem: 'salmon', quantity: 1.5, unit: 'lb' },
          { name: 'olive oil', quantity: 2, unit: 'tbsp' },
        ],
        steps: [{ text: 'Roast the salmon.', ingredientRefs: ['salmon'] }],
      },
    ],
  };

  test('passes a good file', () => {
    assert.deepEqual(lintSeedRecipes(GOOD_SEED, GOOD_CANONICAL), []);
  });

  test('catches an ingredient with no canonical item, which would land in other', () => {
    const problems = lintSeedRecipes(
      { ...GOOD_SEED, recipes: [{ ...GOOD_SEED.recipes[0], ingredients: [{ name: 'dragonfruit powder' }] }] },
      GOOD_CANONICAL
    );
    assert.match(problems.join(' '), /not a canonical item or alias/);
  });

  test('catches a step pointing at an ingredient the recipe does not have', () => {
    const problems = lintSeedRecipes(
      { ...GOOD_SEED, recipes: [{ ...GOOD_SEED.recipes[0], steps: [{ text: 'Cook.', ingredientRefs: ['butter'] }] }] },
      GOOD_CANONICAL
    );
    assert.match(problems.join(' '), /does not list as an ingredient/);
  });

  test('enforces the no em dash rule from section 11', () => {
    const problems = lintSeedRecipes(
      { ...GOOD_SEED, recipes: [{ ...GOOD_SEED.recipes[0], title: 'Salmon — Quick' }] },
      GOOD_CANONICAL
    );
    assert.match(problems.join(' '), /em dash/);
  });

  test('catches duplicate ids and bad numbers', () => {
    const problems = lintSeedRecipes(
      { ...GOOD_SEED, recipes: [GOOD_SEED.recipes[0], { ...GOOD_SEED.recipes[0], baseServings: 0, totalMinutes: -1 }] },
      GOOD_CANONICAL
    );
    assert.match(problems.join(' '), /duplicate id/);
    assert.match(problems.join(' '), /baseServings/);
    assert.match(problems.join(' '), /totalMinutes/);
  });

  test('rejects a unit outside the supported set', () => {
    const problems = lintSeedRecipes(
      { ...GOOD_SEED, recipes: [{ ...GOOD_SEED.recipes[0], ingredients: [{ name: 'olive oil', unit: 'glug' }] }] },
      GOOD_CANONICAL
    );
    assert.match(problems.join(' '), /unknown unit/);
  });
});

describe('the real resource files', () => {
  test('canonical_items.json is valid', () => {
    assert.deepEqual(lintCanonicalItems(read('canonical_items.json')), []);
  });

  test('canonical_items.json covers every aisle that holds food', () => {
    const doc = read('canonical_items.json');
    const used = new Set(doc.items.map((i) => i.aisle));
    for (const aisle of AISLES) {
      // "other" is the catch-all for unmatched items, so it is seeded empty.
      if (aisle === 'other') continue;
      assert.ok(used.has(aisle), `no canonical items in aisle "${aisle}"`);
    }
  });

  test('canonical_items.json declares the units from section 4', () => {
    assert.deepEqual(read('canonical_items.json').units, UNITS);
  });

  test('the pantry staples from section 12 are all marked as staples', () => {
    const doc = read('canonical_items.json');
    const staples = new Set(doc.items.filter((i) => i.isStaple).flatMap((i) => [i.name, ...(i.aliases ?? [])]));
    for (const expected of ['salt', 'black pepper', 'olive oil', 'butter', 'garlic', 'onion', 'flour', 'sugar', 'rice', 'soy sauce']) {
      assert.ok(staples.has(expected), `"${expected}" should be a staple, per section 12`);
    }
  });
});
