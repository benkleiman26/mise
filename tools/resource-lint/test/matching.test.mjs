import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { readFileSync } from 'node:fs';

import {
  buildIndex, containmentMatches, keys, lintMatchingFixtures, lintSeedResolution,
  normalize, resolve, variants, withoutDescriptors,
} from '../src/matching.mjs';

const read = (name) => JSON.parse(readFileSync(new URL(name, import.meta.url), 'utf8'));
const FIXTURES = read('../../../MiseTests/Fixtures/canonical_matching.json');
const CANONICAL = read('../../../Mise/Resources/canonical_items.json');
const SEED = read('../../../Mise/Resources/seed_recipes.json');

describe('the real corpus against the real table', () => {
  test('every case checks out', () => {
    assert.deepEqual(lintMatchingFixtures(FIXTURES, CANONICAL), []);
  });

  test('every seed ingredient resolves to the item the seed names', () => {
    assert.deepEqual(lintSeedResolution(SEED, CANONICAL), []);
  });

  test('every canonical name and alias resolves to itself', () => {
    const index = buildIndex(CANONICAL.items);
    const wrong = [];
    for (const item of CANONICAL.items) {
      for (const phrase of [item.name, ...(item.aliases ?? [])]) {
        const got = resolve(phrase, CANONICAL.items, index);
        if (got?.name !== item.name) wrong.push(`"${phrase}" resolved to ${got?.name ?? 'nothing'}, expected ${item.name}`);
      }
    }
    assert.deepEqual(wrong, []);
  });
});

describe('lintMatchingFixtures catches a bad case', () => {
  const withCases = (cases) => ({ ...FIXTURES, cases: [...FIXTURES.cases, ...cases] });

  test('an item that is not in the table', () => {
    const problems = lintMatchingFixtures(
      withCases([{ input: 'quinoa flour', item: 'quinoa flour', aisle: 'bakingAndSpices', reason: 'exactName', confidence: 'high' }]),
      CANONICAL
    );
    assert.match(problems.join(' '), /is not an item in canonical_items\.json/);
  });

  test('the wrong aisle', () => {
    const problems = lintMatchingFixtures(
      withCases([{ input: 'olive oil', item: 'olive oil', aisle: 'produce', reason: 'exactName', confidence: 'high' }]),
      CANONICAL
    );
    assert.match(problems.join(' '), /is in aisle oilsAndCondiments, not produce/);
  });

  test('a claimed alias that is not one', () => {
    const problems = lintMatchingFixtures(
      withCases([{ input: 'cooking oil', item: 'olive oil', aisle: 'oilsAndCondiments', reason: 'alias', confidence: 'high' }]),
      CANONICAL
    );
    assert.match(problems.join(' '), /claims alias, but it is not one of/);
  });

  test('a claimed no-match that actually matches', () => {
    const problems = lintMatchingFixtures(
      withCases([{ input: 'kosher salt', item: null, aisle: 'other', reason: 'none', confidence: 'low' }]),
      CANONICAL
    );
    assert.match(problems.join(' '), /expects no match, but it resolves to "kosher salt"/);
  });

  test('an unmatched ingredient filed somewhere other than other', () => {
    const problems = lintMatchingFixtures(
      withCases([{ input: 'zzzz nonsense', item: null, aisle: 'produce', reason: 'none', confidence: 'low' }]),
      CANONICAL
    );
    assert.match(problems.join(' '), /belongs in aisle other/);
  });

  test('containment claimed where the head noun disagrees', () => {
    const problems = lintMatchingFixtures(
      withCases([{ input: 'milk chocolate bar', item: 'milk', aisle: 'dairyAndEggs', reason: 'contained', confidence: 'medium' }]),
      CANONICAL
    );
    assert.match(problems.join(' '), /the words or the head noun do not line up/);
  });

  test('a learned alias that already matches, so teaches nothing', () => {
    const doc = { ...FIXTURES, learnedAliases: [{ input: 'salt', teach: 'salt', item: 'kosher salt', aisle: 'bakingAndSpices' }] };
    assert.match(lintMatchingFixtures(doc, CANONICAL).join(' '), /it already matches, so it teaches nothing/);
  });

  test('a corpus missing a rung of the ladder', () => {
    const doc = { ...FIXTURES, cases: FIXTURES.cases.filter((c) => c.reason !== 'contained') };
    assert.match(lintMatchingFixtures(doc, CANONICAL).join(' '), /no longer covers the "contained" rung/);
  });
});

describe('lintSeedResolution', () => {
  test('notices an ingredient with no canonical link', () => {
    const broken = { recipes: [{ title: 'X', ingredients: [{ name: 'moon dust' }] }] };
    assert.match(lintSeedResolution(broken, CANONICAL).join(' '), /has no canonicalItem/);
  });

  test('notices a link that does not match what resolution gives', () => {
    const broken = { recipes: [{ title: 'X', ingredients: [{ name: 'olive oil', canonicalItem: 'butter' }] }] };
    assert.match(lintSeedResolution(broken, CANONICAL).join(' '), /resolves to "olive oil", but the seed says "butter"/);
  });
});

describe('the rules themselves', () => {
  test('normalize folds case, accents and punctuation', () => {
    assert.equal(normalize('Extra-Virgin Olive Oil'), 'extra virgin olive oil');
    assert.equal(normalize('  jalapeño  '), 'jalapeno');
    assert.equal(normalize(',,,'), '');
  });

  test('variants bridge singular and plural without mangling words', () => {
    assert.ok(variants('carrots').includes('carrot'));
    assert.ok(variants('carrot').includes('carrots'));
    assert.ok(variants('berries').includes('berry'));
  });

  test('keys vary only the last word', () => {
    assert.ok(keys('green beans').includes('green bean'));
    assert.ok(!keys('green beans').some((k) => k.startsWith('greens ')));
  });

  test('descriptors come off', () => {
    assert.equal(withoutDescriptors('large ripe avocado'), 'avocado');
    assert.equal(withoutDescriptors('olive oil'), 'olive oil');
  });

  test('containment needs the head noun to agree', () => {
    assert.equal(containmentMatches('low sodium soy sauce', 'soy sauce'), true);
    assert.equal(containmentMatches('milk chocolate', 'milk'), false, 'the trap');
    assert.equal(containmentMatches('olive oil spray', 'olive oil'), false);
  });

  test('the most specific item wins', () => {
    const index = buildIndex(CANONICAL.items);
    assert.equal(resolve('canned coconut milk', CANONICAL.items, index).name, 'coconut milk');
  });
});

describe('regressions from the first real compile', () => {
  test('a containment claim that descriptor stripping already answers is refused', () => {
    // This is what let "good quality balsamic vinegar" sit in the corpus
    // labelled contained when the Swift correctly called it normalized.
    const doc = {
      ...FIXTURES,
      cases: [
        ...FIXTURES.cases,
        { input: 'good quality balsamic vinegar', item: 'balsamic vinegar', aisle: 'oilsAndCondiments', reason: 'contained', confidence: 'medium' },
      ],
    };
    assert.match(lintMatchingFixtures(doc, CANONICAL).join(' '), /dropping descriptors gives "balsamic vinegar", which matches first/);
  });

  test('cooked is a descriptor, so shipped recipes do not ask the user about rice', () => {
    const index = buildIndex(CANONICAL.items);
    assert.equal(resolve('cooked white rice', CANONICAL.items, index).name, 'white rice');
    assert.equal(resolve('cooked quinoa', CANONICAL.items, index).name, 'quinoa');
    assert.equal(withoutDescriptors('cooked white rice'), 'white rice');
  });
});
