import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { readFileSync } from 'node:fs';

import { combine, fraction, lintUnitFixtures } from '../src/units.mjs';

const FIXTURES = JSON.parse(readFileSync(new URL('../../../MiseTests/Fixtures/unit_conversion.json', import.meta.url), 'utf8'));

describe('the real fixture file', () => {
  test('every expected value follows from the multipliers', () => {
    assert.deepEqual(lintUnitFixtures(FIXTURES), []);
  });

  test('covers the rules section 4 actually states', () => {
    const conversions = FIXTURES.conversions;
    assert.ok(conversions.some((c) => c.expected === null), 'a refused cross-family conversion');
    assert.ok(conversions.some((c) => c.from === c.to), 'identity');
    assert.ok(
      FIXTURES.combinations.some((c) => c.expected.length > 1),
      'a combination that has to keep both quantities'
    );
    assert.ok(
      FIXTURES.combinations.some((c) => c.input.length > 1 && c.expected.length === 1),
      'a combination that merges'
    );
    assert.ok(FIXTURES.combinations.some((c) => c.formatted?.includes(' + ')), 'the "1 cup + 2 tbsp" format');
  });
});

describe('lintUnitFixtures catches a bad fixture', () => {
  const withConversions = (conversions) => ({ ...FIXTURES, conversions });

  test('a wrong expected value', () => {
    const problems = lintUnitFixtures(withConversions([{ quantity: 1, from: 'cup', to: 'tbsp', expected: 15 }]));
    assert.match(problems.join(' '), /fixture says 15, the multipliers give 16/);
  });

  test('a cross-family conversion claimed to work', () => {
    const problems = lintUnitFixtures(withConversions([{ quantity: 1, from: 'cup', to: 'g', expected: 236 }]));
    assert.match(problems.join(' '), /not convertible/);
  });

  test('a same-family conversion claimed impossible', () => {
    const problems = lintUnitFixtures(withConversions([{ quantity: 1, from: 'cup', to: 'tbsp', expected: null }]));
    assert.match(problems.join(' '), /expects no conversion, but one is possible/);
  });

  test('a unit filed in no family, or in two', () => {
    const { l, ...rest } = FIXTURES.families.volume.reduce((o, u) => ({ ...o, [u]: true }), {});
    const narrowed = { ...FIXTURES, families: { ...FIXTURES.families, volume: FIXTURES.families.volume.filter((u) => u !== 'l') } };
    assert.match(lintUnitFixtures(narrowed).join(' '), /unit "l" is in no family/);

    const doubled = { ...FIXTURES, families: { ...FIXTURES.families, mass: [...FIXTURES.families.mass, 'cup'] } };
    assert.match(lintUnitFixtures(doubled).join(' '), /unit "cup" is in more than one family/);
  });

  test('a discrete unit given a multiplier', () => {
    const doc = { ...FIXTURES, multipliers: { ...FIXTURES.multipliers, can: 400 } };
    assert.match(lintUnitFixtures(doc).join(' '), /"can" is discrete, so it must not have a multiplier/);
  });

  test('a formatted string that does not match the rules', () => {
    const doc = { ...FIXTURES, combinations: [{ input: [[3, 'tbsp'], [2, 'tsp']], expected: [[3.6667, 'tbsp']], formatted: '3.67 tbsp' }] };
    assert.match(lintUnitFixtures(doc).join(' '), /render "3 2\/3 tbsp"/);
  });

  test('a wrong fraction', () => {
    const doc = { ...FIXTURES, fractions: [{ value: 1.5, expected: '1.5' }] };
    assert.match(lintUnitFixtures(doc).join(' '), /fixture says "1.5", the rules give "1 1\/2"/);
  });
});

describe('the merge rule itself', () => {
  const { families, multipliers } = FIXTURES;

  test('keeps mass and volume apart in one call', () => {
    const out = combine([[1, 'cup'], [100, 'g'], [1, 'tbsp']], families, multipliers);
    assert.equal(out.length, 2);
    assert.equal(out[0][1], 'cup');
    assert.equal(out[1][1], 'g');
  });

  test('preserves the order the measurements arrived in', () => {
    const out = combine([[100, 'g'], [1, 'cup']], families, multipliers);
    assert.deepEqual(out.map((m) => m[1]), ['g', 'cup']);
  });

  test('never merges two different discrete units', () => {
    const out = combine([[2, 'can'], [1, 'bunch'], [3, 'can']], families, multipliers);
    assert.deepEqual(out, [[5, 'can'], [1, 'bunch']]);
  });
});

describe('fraction', () => {
  test('uses the fractions a measuring cup has', () => {
    assert.equal(fraction(1.5), '1 1/2');
    assert.equal(fraction(0.3333), '1/3');
    assert.equal(fraction(2.25), '2 1/4');
  });

  test('shows a decimal rather than inventing a fraction', () => {
    assert.equal(fraction(0.4), '0.4');
    assert.equal(fraction(1.07), '1.07');
  });

  test('handles zero and whole numbers', () => {
    assert.equal(fraction(0), '0');
    assert.equal(fraction(3), '3');
  });
});
