import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { readFileSync } from 'node:fs';

import { generate, lintListFixtures } from '../src/list.mjs';

const read = (name) => JSON.parse(readFileSync(new URL(name, import.meta.url), 'utf8'));
const FIXTURES = read('../../../MiseTests/Fixtures/list_generation.json');
const CANONICAL = read('../../../Mise/Resources/canonical_items.json');
const SEED = read('../../../Mise/Resources/seed_recipes.json');

describe('the real scenarios against the real recipes', () => {
  test('every expected list follows from the seed data', () => {
    assert.deepEqual(lintListFixtures(FIXTURES, SEED, CANONICAL), []);
  });
});

describe('lintListFixtures catches a bad scenario', () => {
  const withScenarios = (scenarios) => ({ ...FIXTURES, scenarios });

  test('a quantity the recipes do not add up to', () => {
    const scenario = structuredClone(FIXTURES.scenarios[0]);
    scenario.expect.find((i) => i.item === 'salmon').formatted = '4 lb';
    assert.match(lintListFixtures(withScenarios([scenario]), SEED, CANONICAL).join(' '), /reads "3 lb", the fixture says "4 lb"/);
  });

  test('an item in the wrong aisle', () => {
    const scenario = structuredClone(FIXTURES.scenarios[0]);
    scenario.expect.find((i) => i.item === 'salmon').aisle = 'produce';
    assert.match(lintListFixtures(withScenarios([scenario]), SEED, CANONICAL).join(' '), /is in aisle seafood, the fixture says produce/);
  });

  test('a staple the pantry should have removed', () => {
    const scenario = structuredClone(FIXTURES.scenarios[0]);
    scenario.expectAbsent = [];
    scenario.expect.push({ item: 'olive oil', aisle: 'oilsAndCondiments', formatted: '3 tbsp', sources: 1 });
    assert.match(lintListFixtures(withScenarios([scenario]), SEED, CANONICAL).join(' '), /expects 5 items, the rules give 4/);
  });

  test('an item claimed absent that is on the list', () => {
    const scenario = structuredClone(FIXTURES.scenarios[0]);
    scenario.expectAbsent = ['salmon'];
    assert.match(lintListFixtures(withScenarios([scenario]), SEED, CANONICAL).join(' '), /"salmon" should not be on the list/);
  });

  test('a recipe that is not in the seed library', () => {
    const scenario = structuredClone(FIXTURES.scenarios[0]);
    scenario.plan = [{ recipe: 'seed-does-not-exist', servings: 4 }];
    assert.match(lintListFixtures(withScenarios([scenario]), SEED, CANONICAL).join(' '), /unknown recipe seed-does-not-exist/);
  });

  test('scenarios that no longer cover a rule', () => {
    const noMerge = FIXTURES.scenarios.filter((s) => !(s.expect ?? []).some((i) => i.sources > 1));
    assert.match(lintListFixtures(withScenarios(noMerge), SEED, CANONICAL).join(' '), /no longer cover an ingredient merged across recipes/);
  });
});

describe('the generation rules', () => {
  const run = (scenario) => generate(scenario, SEED, CANONICAL);

  test('rule 1: servings scale the quantities', () => {
    const four = run({ plan: [{ recipe: 'seed-sheet-pan-salmon', servings: 4 }], pantryHave: 'allStaples' });
    const eight = run({ plan: [{ recipe: 'seed-sheet-pan-salmon', servings: 8 }], pantryHave: 'allStaples' });
    assert.equal(four.find((i) => i.item === 'green beans').formatted, '1 lb');
    assert.equal(eight.find((i) => i.item === 'green beans').formatted, '2 lb');
  });

  test('rule 3: quantities in one family add, across families they do not', () => {
    const tacos = run({
      plan: [{ recipe: 'seed-shrimp-tacos', servings: 4 }, { recipe: 'seed-fish-tacos-cod', servings: 4 }],
      pantryHave: 'allStaples',
    });
    assert.equal(tacos.find((i) => i.item === 'corn tortillas').formatted, '16', 'same unit adds');
    assert.equal(tacos.find((i) => i.item === 'cabbage').formatted, '1/2 + 3 cups', 'across families, keep both');
  });

  test('rule 4: the pantry is what removes staples, not a hardcoded list', () => {
    const stocked = run({ plan: [{ recipe: 'seed-sheet-pan-salmon', servings: 4 }], pantryHave: 'allStaples' });
    const bare = run({ plan: [{ recipe: 'seed-sheet-pan-salmon', servings: 4 }], pantryHave: [] });
    assert.equal(stocked.some((i) => i.item === 'olive oil'), false);
    assert.equal(bare.some((i) => i.item === 'olive oil'), true);
  });

  test('rule 5: aisles come in the household walk order', () => {
    const list = run({
      plan: [{ recipe: 'seed-shrimp-tacos', servings: 4 }, { recipe: 'seed-fish-tacos-cod', servings: 4 }],
      pantryHave: 'allStaples',
    });
    const positions = list.map((i) => CANONICAL.aisleOrder.indexOf(i.aisle));
    assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
  });

  test('an empty plan gives an empty list', () => {
    assert.deepEqual(run({ plan: [], pantryHave: 'allStaples' }), []);
  });
});
