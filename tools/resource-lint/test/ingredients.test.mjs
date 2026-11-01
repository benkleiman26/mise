import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { readFileSync } from 'node:fs';

import { leadingQuantity, lintIngredientFixtures } from '../src/ingredients.mjs';

const FIXTURES = JSON.parse(
  readFileSync(new URL('../../../MiseTests/Fixtures/ingredient_parsing.json', import.meta.url), 'utf8')
);

const withCases = (cases) => ({ ...FIXTURES, cases: [...FIXTURES.cases, ...cases] });

describe('the real corpus', () => {
  test('every case is self consistent', () => {
    assert.deepEqual(lintIngredientFixtures(FIXTURES), []);
  });

  test('is big enough to be worth having', () => {
    assert.ok(FIXTURES.cases.length >= 50, `only ${FIXTURES.cases.length} cases`);
  });

  test('carries the example section 1a complains about', () => {
    assert.ok(
      FIXTURES.cases.some((c) => c.input.includes('asparagus, tough ends removed')),
      'the line Mealime kept raw should be covered'
    );
  });
});

describe('lintIngredientFixtures catches a bad case', () => {
  test('a name that was never in the input', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: '2 cups flour', quantity: 2, unit: 'cup', name: 'sugar', confidence: 'high' }])
    );
    assert.match(problems.join(' '), /expected name "sugar" does not appear/);
  });

  test('a preparation that was never in the input', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: '2 cups flour', quantity: 2, unit: 'cup', name: 'flour', preparation: 'sifted', confidence: 'high' }])
    );
    assert.match(problems.join(' '), /expected preparation "sifted" does not appear/);
  });

  test('a quantity that disagrees with the line', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: '1/2 cup milk', quantity: 2, unit: 'cup', name: 'milk', confidence: 'high' }])
    );
    assert.match(problems.join(' '), /expects quantity 2, the line reads 0.5/);
  });

  test('a quantity claimed where the line has none', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: 'Salt', quantity: 1, unit: null, name: 'Salt', confidence: 'high' }])
    );
    assert.match(problems.join(' '), /does not start with a number/);
  });

  test('no quantity claimed where the line starts with one', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: '2 cups flour', quantity: null, unit: 'cup', name: 'flour', confidence: 'high' }])
    );
    assert.match(problems.join(' '), /expects no quantity, but the line starts with a number/);
  });

  test('a unit that is not in section 4', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: '2 scoops flour', quantity: 2, unit: 'scoop', name: 'flour', confidence: 'high' }])
    );
    assert.match(problems.join(' '), /"scoop" is not one of the units/);
  });

  test('optional claimed on a line that never says so', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: '2 cups flour', quantity: 2, unit: 'cup', name: 'flour', isOptional: true, confidence: 'high' }])
    );
    assert.match(problems.join(' '), /marked optional, but the line never says so/);
  });

  test('a name that still carries its unit', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: '2 cups flour', quantity: 2, unit: 'cup', name: 'cups flour', confidence: 'high' }])
    );
    assert.match(problems.join(' '), /the name still starts with the unit "cup"/);
  });

  test('a missing confidence', () => {
    const problems = lintIngredientFixtures(
      withCases([{ input: '2 cups flour', quantity: 2, unit: 'cup', name: 'flour' }])
    );
    assert.match(problems.join(' '), /confidence should be one of/);
  });

  test('the same input twice', () => {
    const duplicate = FIXTURES.cases[0];
    assert.match(lintIngredientFixtures(withCases([duplicate])).join(' '), /the same input appears twice/);
  });

  test('a corpus that has quietly got easier', () => {
    const noRanges = { ...FIXTURES, cases: FIXTURES.cases.filter((c) => !/\d\s*(?:-|–|to)\s*\d/.test(c.input)) };
    assert.match(lintIngredientFixtures(noRanges).join(' '), /no longer covers ranges/);

    const noUnicode = { ...FIXTURES, cases: FIXTURES.cases.filter((c) => !/[¼-¾⅐-⅞]/.test(c.input)) };
    assert.match(lintIngredientFixtures(noUnicode).join(' '), /no longer covers unicode fractions/);
  });
});

describe('leadingQuantity', () => {
  test('reads the forms recipes actually use', () => {
    assert.equal(leadingQuantity('2 cups flour'), 2);
    assert.equal(leadingQuantity('1.5 kg chicken'), 1.5);
    assert.equal(leadingQuantity('1/2 cup milk'), 0.5);
    assert.equal(leadingQuantity('1 1/2 pounds salmon'), 1.5);
    assert.equal(leadingQuantity('½ cup soy sauce'), 0.5);
    assert.equal(leadingQuantity('1½ cups rice'), 1.5);
  });

  test('takes the lower bound of a range', () => {
    assert.equal(leadingQuantity('1 to 2 cloves garlic'), 1);
    assert.equal(leadingQuantity('2-3 tablespoons oil'), 2);
  });

  test('looks past an optional marker', () => {
    assert.equal(leadingQuantity('Optional: 2 tablespoons sesame seeds'), 2);
  });

  test('returns nothing when the line has no number up front', () => {
    assert.equal(leadingQuantity('Salt'), null);
    assert.equal(leadingQuantity('Juice of 1 lemon'), null);
    assert.equal(leadingQuantity(''), null);
  });
});
