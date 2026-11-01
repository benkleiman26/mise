// Validates MiseTests/Fixtures/list_generation.json.
//
// The scenarios reference real seed recipes by id, so the expected grocery list
// is not invented: it is recomputed here from the actual recipe data, the real
// canonical table, and the unit arithmetic already mirrored in units.mjs.
//
// That makes this the strongest of the fixture checks. A scenario cannot claim
// a quantity the recipes do not add up to, cannot put an item in the wrong
// aisle, and cannot forget that a staple should have been dropped.

import { readFileSync } from 'node:fs';
import { combine, formatOne } from './units.mjs';
import { normalize } from './matching.mjs';

const UNIT_FIXTURES = JSON.parse(
  readFileSync(new URL('../../../MiseTests/Fixtures/unit_conversion.json', import.meta.url), 'utf8')
);
const FAMILIES = UNIT_FIXTURES.families;
const MULTIPLIERS = UNIT_FIXTURES.multipliers;

/** Section 5.3 rules 1 to 5, as a function, for checking the fixture. */
export function generate(scenario, seed, canonical) {
  const recipesById = new Map(seed.recipes.map((r) => [r.id, r]));
  const itemsByName = new Map(canonical.items.map((i) => [normalize(i.name), i]));
  const aisleOrder = canonical.aisleOrder;

  const have = new Set(
    (scenario.pantryHave === 'allStaples'
      ? canonical.items.filter((i) => i.isStaple).map((i) => i.name)
      : scenario.pantryHave ?? []
    ).map(normalize)
  );

  // Rule 1: expand each planned meal, scaled by servings over baseServings.
  // Rule 2 is already done in the seed data, which carries canonicalItem.
  // Rule 4: drop what the pantry says we have.
  const groups = new Map();
  for (const entry of scenario.plan ?? []) {
    const recipe = recipesById.get(entry.recipe);
    if (!recipe) throw new Error(`scenario references unknown recipe ${entry.recipe}`);
    const factor = entry.servings / recipe.baseServings;

    for (const ingredient of recipe.ingredients) {
      const key = normalize(ingredient.canonicalItem);
      if (have.has(key)) continue;
      if (!groups.has(key)) groups.set(key, { key, quantities: [], sources: new Set(), optional: true });
      const group = groups.get(key);
      group.quantities.push([(ingredient.quantity ?? 0) * factor, ingredient.unit ?? null]);
      group.sources.add(recipe.id);
      // An item is only optional if every recipe that wants it says so.
      if (!ingredient.isOptional) group.optional = false;
    }
  }

  // Rule 3: merge, summing inside a family and keeping both across families.
  const items = [...groups.values()].map((group) => {
    const merged = combine(group.quantities, FAMILIES, MULTIPLIERS);
    const item = itemsByName.get(group.key);
    return {
      item: item ? item.name : group.key,
      // Rule 2 again: whatever did not resolve still has to land somewhere.
      aisle: item ? item.aisle : 'other',
      quantities: merged,
      formatted: merged.map((m) => formatOne(m, FAMILIES)).join(' + '),
      sources: group.sources.size,
      isOptional: group.optional,
    };
  });

  // Rule 5: group by aisle in the household's walk order.
  items.sort((a, b) => {
    const byAisle = aisleOrder.indexOf(a.aisle) - aisleOrder.indexOf(b.aisle);
    return byAisle !== 0 ? byAisle : a.item.localeCompare(b.item);
  });

  return items;
}

export function lintListFixtures(doc, seed, canonical) {
  const problems = [];
  const fail = (message) => problems.push(message);

  if (doc?.format !== 'list-generation-fixtures') {
    fail(`format should be "list-generation-fixtures", got ${JSON.stringify(doc?.format)}`);
  }

  const scenarios = doc?.scenarios;
  if (!Array.isArray(scenarios) || scenarios.length === 0) {
    fail('scenarios should be a non-empty array');
    return problems;
  }

  const seen = new Set();
  for (const scenario of scenarios) {
    const where = `"${scenario?.name ?? '(unnamed)'}"`;
    if (!scenario?.name) fail('a scenario has no name');
    if (seen.has(scenario.name)) fail(`${where}: two scenarios share a name`);
    seen.add(scenario.name);

    let actual;
    try {
      actual = generate(scenario, seed, canonical);
    } catch (error) {
      fail(`${where}: ${error.message}`);
      continue;
    }

    const expected = scenario.expect ?? [];
    if (actual.length !== expected.length) {
      fail(
        `${where}: expects ${expected.length} items, the rules give ${actual.length}: ` +
          actual.map((i) => `${i.item} ${i.formatted}`).join(', ')
      );
      continue;
    }

    for (const [index, line] of actual.entries()) {
      const want = expected[index];
      const at = `${where} line ${index + 1}`;
      if (line.item !== want.item) fail(`${at}: should be "${want.item}", the rules give "${line.item}"`);
      if (line.aisle !== want.aisle) fail(`${at}: "${line.item}" is in aisle ${line.aisle}, the fixture says ${want.aisle}`);
      if (want.formatted !== undefined && line.formatted !== want.formatted) {
        fail(`${at}: "${line.item}" reads "${line.formatted}", the fixture says "${want.formatted}"`);
      }
      if (want.sources !== undefined && line.sources !== want.sources) {
        fail(`${at}: "${line.item}" comes from ${line.sources} recipe(s), the fixture says ${want.sources}`);
      }
    }

    for (const absent of scenario.expectAbsent ?? []) {
      if (actual.some((line) => normalize(line.item) === normalize(absent))) {
        fail(`${where}: "${absent}" should not be on the list, but it is`);
      }
    }
  }

  const has = (predicate, label) => {
    if (!scenarios.some(predicate)) fail(`the scenarios no longer cover ${label}`);
  };
  has((s) => (s.expect ?? []).some((i) => i.sources > 1), 'an ingredient merged across recipes');
  has((s) => (s.expect ?? []).some((i) => (i.formatted ?? '').includes(' + ')), 'quantities that cannot be added');
  has((s) => (s.expectAbsent ?? []).length > 0, 'the pantry removing something');
  has((s) => (s.plan ?? []).some((p) => p.servings !== 4), 'servings that are not the household default');

  return problems;
}
