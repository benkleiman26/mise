// Validates MiseTests/Fixtures/ingredient_parsing.json.
//
// This cannot check that the parser is right, because there is no parser here
// and writing a second one was refused for good reasons (see DECISIONS.md).
// What it can check is that every case is a case: that the expected output is
// made of pieces the input actually contains, that units and quantities are
// legal, and that the corpus still covers the awkward shapes it was built for.
//
// That catches the way hand written fixtures usually go wrong, which is
// expecting something the input never said.

import { UNITS } from './lint.mjs';

const CONFIDENCE = ['high', 'medium', 'low'];

const VULGAR = {
  '½': 0.5, '⅓': 1 / 3, '⅔': 2 / 3, '¼': 0.25, '¾': 0.75,
  '⅕': 0.2, '⅖': 0.4, '⅗': 0.6, '⅘': 0.8, '⅙': 1 / 6, '⅚': 5 / 6, '⅛': 0.125,
  '⅜': 0.375, '⅝': 0.625, '⅞': 0.875,
};

const squash = (text) => String(text ?? '').replace(/\s+/g, ' ').trim().toLowerCase();

/**
 * Reads the quantity off the front of a line. Deliberately small: enough to
 * confirm a fixture's stated quantity, not enough to be a parser.
 */
export function leadingQuantity(input) {
  let text = String(input ?? '').trim().replace(/^optional\s*:\s*/i, '');

  // A range takes its lower bound, so only the first number matters here.
  const vulgarMixed = text.match(/^(\d+)\s*([¼-¾⅐-⅞])/);
  if (vulgarMixed) return Number(vulgarMixed[1]) + (VULGAR[vulgarMixed[2]] ?? NaN);

  const vulgarAlone = text.match(/^([¼-¾⅐-⅞])/);
  if (vulgarAlone) return VULGAR[vulgarAlone[1]] ?? NaN;

  const mixed = text.match(/^(\d+)\s+(\d+)\s*\/\s*(\d+)/);
  if (mixed) return Number(mixed[1]) + Number(mixed[2]) / Number(mixed[3]);

  const fraction = text.match(/^(\d+)\s*\/\s*(\d+)/);
  if (fraction) return Number(fraction[1]) / Number(fraction[2]);

  const decimal = text.match(/^(\d+(?:\.\d+)?)/);
  if (decimal) return Number(decimal[1]);

  return null;
}

export function lintIngredientFixtures(doc) {
  const problems = [];
  const fail = (message) => problems.push(message);

  if (doc?.format !== 'ingredient-parsing-fixtures') {
    fail(`format should be "ingredient-parsing-fixtures", got ${JSON.stringify(doc?.format)}`);
  }

  const cases = doc?.cases;
  if (!Array.isArray(cases) || cases.length === 0) {
    fail('cases should be a non-empty array');
    return problems;
  }

  const seen = new Set();
  for (const entry of cases) {
    const input = entry?.input;
    if (typeof input !== 'string' || !input.trim()) {
      fail('a case has no input');
      continue;
    }
    const where = `"${input.trim()}"`;
    const haystack = squash(input);

    if (seen.has(haystack)) fail(`${where}: the same input appears twice`);
    seen.add(haystack);

    if (entry.unit !== null && entry.unit !== undefined && !UNITS.includes(entry.unit)) {
      fail(`${where}: "${entry.unit}" is not one of the units in section 4`);
    }

    if (entry.quantity !== null && entry.quantity !== undefined) {
      if (typeof entry.quantity !== 'number' || !(entry.quantity > 0)) {
        fail(`${where}: quantity should be a positive number or null`);
      } else {
        // The stated quantity has to be the one actually written on the line.
        const read = leadingQuantity(input);
        if (read === null) {
          fail(`${where}: expects quantity ${entry.quantity} but the line does not start with a number`);
        } else if (Math.abs(read - entry.quantity) > 0.01) {
          fail(`${where}: expects quantity ${entry.quantity}, the line reads ${Math.round(read * 10000) / 10000}`);
        }
      }
    } else if (leadingQuantity(input) !== null) {
      fail(`${where}: expects no quantity, but the line starts with a number`);
    }

    if (typeof entry.name !== 'string' || !entry.name.trim()) {
      fail(`${where}: name is required`);
    } else if (!haystack.includes(squash(entry.name))) {
      fail(`${where}: expected name "${entry.name}" does not appear in the input`);
    }

    for (const field of ['preparation', 'parenthetical']) {
      const value = entry[field];
      if (value === undefined || value === null) continue;
      if (typeof value !== 'string' || !value.trim()) fail(`${where}: ${field} should be a non-empty string or absent`);
      else if (!haystack.includes(squash(value))) fail(`${where}: expected ${field} "${value}" does not appear in the input`);
    }

    if (entry.parenthetical !== undefined && !input.includes('(')) {
      fail(`${where}: expects a parenthetical but the line has no parentheses`);
    }

    if (entry.isOptional === true && !/optional/i.test(input)) {
      fail(`${where}: marked optional, but the line never says so`);
    }
    if (entry.isOptional !== undefined && typeof entry.isOptional !== 'boolean') {
      fail(`${where}: isOptional should be true or false`);
    }

    if (!CONFIDENCE.includes(entry.confidence)) {
      fail(`${where}: confidence should be one of ${CONFIDENCE.join(', ')}`);
    }

    // A name that still carries its unit means the case itself is wrong.
    // Compare the singular too, since the line says "cups" and the unit is "cup".
    const firstWord = squash(entry.name).split(' ')[0];
    const singular = firstWord.replace(/s$/, '');
    if (entry.unit && (firstWord === entry.unit || singular === entry.unit)) {
      fail(`${where}: the name still starts with the unit "${entry.unit}"`);
    }
  }

  // The corpus exists to cover the shapes that break a naive parser. If one
  // stops being covered, the corpus has quietly got easier.
  const has = (predicate, label) => {
    if (!cases.some(predicate)) fail(`the corpus no longer covers ${label}`);
  };
  has((c) => /[¼-¾⅐-⅞]/.test(c.input), 'unicode fractions');
  has((c) => /\d\s*(?:-|–|to)\s*\d/.test(c.input), 'ranges');
  has((c) => c.parenthetical !== undefined, 'parenthetical notes such as a can size');
  has((c) => c.isOptional === true, 'optional ingredients');
  has((c) => c.quantity === null, 'lines with no quantity at all');
  has((c) => c.preparation !== undefined, 'preparation after a comma');
  has((c) => c.confidence === 'low', 'lines we should admit we are unsure about');
  has((c) => c.confidence === 'medium', 'lines worth a review screen');
  has((c) => /\d\s+\d+\s*\//.test(c.input), 'mixed numbers such as 1 1/2');
  has((c) => c.unit === null && c.quantity !== null, 'a count with no unit, such as 2 eggs');

  return problems;
}
