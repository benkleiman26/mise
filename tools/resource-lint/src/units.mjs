// Validates MiseTests/Fixtures/unit_conversion.json.
//
// There is no Swift toolchain in the cloud environment, so the fixtures are
// where UnitConverter's expected behaviour gets checked before it reaches a
// Mac. This recomputes every expected value from the multipliers the fixture
// itself declares, so a wrong number cannot sit in the file looking like a
// requirement.
//
// The merge and format logic below mirrors UnitConverter.swift. That is
// duplication on purpose and the only duplication worth having here: it checks
// the test data, not the app, and if the two ever disagree the Swift tests say
// so rather than the fixture quietly being wrong.

import { UNITS } from './lint.mjs';

const EPSILON = 1e-9;
const PLURALIZES = new Set(['cup', 'pinch', 'clove', 'can', 'bunch', 'package']);
const ABBREVIATION = {
  count: '', tsp: 'tsp', tbsp: 'tbsp', cup: 'cup', floz: 'fl oz', oz: 'oz', lb: 'lb',
  g: 'g', kg: 'kg', ml: 'ml', l: 'l', pinch: 'pinch', clove: 'clove', can: 'can',
  bunch: 'bunch', package: 'package',
};
const FRACTIONS = [
  [1 / 8, '1/8'], [1 / 4, '1/4'], [1 / 3, '1/3'], [1 / 2, '1/2'], [2 / 3, '2/3'], [3 / 4, '3/4'],
];

const round = (value) => {
  const scaled = Math.round(value * 10000) / 10000;
  return Math.abs(scaled) < EPSILON ? 0 : scaled;
};

export function fraction(quantity) {
  const rounded = round(quantity);
  if (!(rounded > 0)) return '0';
  const whole = Math.floor(rounded + EPSILON);
  const remainder = rounded - whole;
  if (remainder < 0.01) return String(whole);
  for (const [value, text] of FRACTIONS) {
    if (Math.abs(remainder - value) < 0.02) return whole > 0 ? `${whole} ${text}` : text;
  }
  const text = rounded.toFixed(2);
  return text.endsWith('0') ? text.slice(0, -1) : text;
}

/** English plurals: an s is wrong after ch, sh, s, x or z. */
export function pluralize(name) {
  return /(?:ch|sh|s|x|z)$/.test(name) ? `${name}es` : `${name}s`;
}

export function formatOne([quantity, unit], families) {
  const amount = fraction(quantity);
  if (!unit || unit === 'count') return amount;
  const name = ABBREVIATION[unit] ?? unit;
  return `${amount} ${PLURALIZES.has(unit) && quantity > 1 + EPSILON ? pluralize(name) : name}`;
}

const familyOf = (unit, families) => {
  if (!unit) return null;
  for (const [family, units] of Object.entries(families)) if (units.includes(unit)) return family;
  return null;
};

/** Mirrors UnitConverter.combine. */
export function combine(input, families, multipliers) {
  const buckets = new Map();
  for (const [quantity, unit] of input) {
    const family = familyOf(unit, families);
    const key = family === 'discrete' || family === null ? `u:${unit ?? ''}` : `f:${family}`;
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push([quantity, unit]);
  }

  return [...buckets.values()].map((group) => {
    if (group.length === 1) return group[0];
    const [, firstUnit] = group[0];
    if (multipliers[firstUnit] === undefined) {
      return [round(group.reduce((sum, [q]) => sum + q, 0)), firstUnit];
    }
    const total = group.reduce((sum, [q, u]) => sum + q * multipliers[u], 0);
    const candidates = [...new Set(group.map(([, u]) => u))]
      .filter((u) => multipliers[u] !== undefined)
      .sort((a, b) => multipliers[b] - multipliers[a]);
    for (const candidate of candidates) {
      const amount = total / multipliers[candidate];
      if (amount >= 1 - EPSILON) return [round(amount), candidate];
    }
    const smallest = candidates.at(-1);
    return [round(total / multipliers[smallest]), smallest];
  });
}

function convert(quantity, from, to, families, multipliers) {
  if (from === to) return quantity;
  if (multipliers[from] === undefined || multipliers[to] === undefined) return null;
  if (familyOf(from, families) !== familyOf(to, families)) return null;
  return (quantity * multipliers[from]) / multipliers[to];
}

const close = (a, b) => a !== null && b !== null && Math.abs(a - b) < 1e-3;

export function lintUnitFixtures(doc) {
  const problems = [];
  const fail = (message) => problems.push(message);

  if (doc?.format !== 'unit-conversion-fixtures') fail(`format should be "unit-conversion-fixtures", got ${JSON.stringify(doc?.format)}`);

  const families = doc?.families ?? {};
  const multipliers = doc?.multipliers ?? {};

  // Every unit from section 4 belongs to exactly one family.
  const placed = Object.values(families).flat();
  for (const unit of UNITS) {
    const count = placed.filter((u) => u === unit).length;
    if (count === 0) fail(`unit "${unit}" is in no family`);
    if (count > 1) fail(`unit "${unit}" is in more than one family`);
  }
  for (const unit of placed) if (!UNITS.includes(unit)) fail(`"${unit}" is not one of the units in section 4`);

  // Convertible units have a multiplier, discrete ones must not.
  for (const unit of [...(families.volume ?? []), ...(families.mass ?? [])]) {
    if (multipliers[unit] === undefined) fail(`"${unit}" is convertible but has no multiplier`);
  }
  for (const unit of families.discrete ?? []) {
    if (multipliers[unit] !== undefined) fail(`"${unit}" is discrete, so it must not have a multiplier`);
  }
  for (const [family, base] of Object.entries(doc?.baseUnits ?? {})) {
    if (multipliers[base] !== 1) fail(`the ${family} base unit "${base}" should have a multiplier of 1`);
  }

  for (const entry of doc?.conversions ?? []) {
    const actual = convert(entry.quantity, entry.from, entry.to, families, multipliers);
    const label = `${entry.quantity} ${entry.from} to ${entry.to}`;
    if (entry.expected === null) {
      if (actual !== null) fail(`${label}: fixture expects no conversion, but one is possible (${round(actual)})`);
    } else if (actual === null) {
      fail(`${label}: fixture expects ${entry.expected}, but these units are not convertible`);
    } else if (!close(round(actual), entry.expected)) {
      fail(`${label}: fixture says ${entry.expected}, the multipliers give ${round(actual)}`);
    }
  }

  for (const entry of doc?.combinations ?? []) {
    const actual = combine(entry.input ?? [], families, multipliers);
    const label = `combine ${JSON.stringify(entry.input)}`;
    const expected = entry.expected ?? [];
    if (actual.length !== expected.length) {
      fail(`${label}: fixture expects ${expected.length} measurement(s), the rules give ${actual.length}`);
      continue;
    }
    for (const [index, [quantity, unit]] of actual.entries()) {
      const [expectedQuantity, expectedUnit] = expected[index];
      if ((unit ?? null) !== (expectedUnit ?? null)) fail(`${label}: part ${index + 1} should be in ${expectedUnit}, the rules give ${unit}`);
      else if (!close(quantity, expectedQuantity)) fail(`${label}: part ${index + 1} should be ${expectedQuantity}, the rules give ${quantity}`);
    }
    const formatted = actual.map((m) => formatOne(m, families)).join(' + ');
    if (entry.formatted !== undefined && formatted !== entry.formatted) {
      fail(`${label}: fixture reads "${entry.formatted}", the rules render "${formatted}"`);
    }
  }

  for (const entry of doc?.fractions ?? []) {
    const actual = fraction(entry.value);
    if (actual !== entry.expected) fail(`fraction ${entry.value}: fixture says "${entry.expected}", the rules give "${actual}"`);
  }

  return problems;
}
