// Validates MiseTests/Fixtures/canonical_matching.json against the real
// canonical item table.
//
// This is the strongest of the three fixture checks, because the expectations
// are not free text: every item named here must exist in canonical_items.json,
// in the aisle claimed, and each case's stated reason must actually hold. A
// case claiming an alias match is checked against that item's aliases; a case
// claiming no match is checked to be sure nothing would have matched.
//
// The normalization below mirrors CanonicalMatcher.swift, which is the same
// deliberate duplication as the other fixture validators: it checks the test
// data, and if it ever drifts the Swift tests fail rather than the fixture
// quietly being wrong.

const REASONS = ['exactName', 'alias', 'normalized', 'contained', 'none'];
const CONFIDENCE = ['high', 'medium', 'low'];

/// Words that describe a thing without changing which thing it is.
const DESCRIPTORS = new Set([
  'large', 'medium', 'small', 'extra', 'jumbo', 'mini', 'baby',
  'fresh', 'freshly', 'ripe', 'good', 'quality', 'organic', 'raw',
]);

export function normalize(text) {
  return String(text ?? '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export const tokens = (text) => normalize(text).split(' ').filter(Boolean);

/** Naive singular and plural, enough to bridge "carrot" and "carrots". */
export function variants(word) {
  const out = new Set([word]);
  if (word.endsWith('ies') && word.length > 4) out.add(`${word.slice(0, -3)}y`);
  if (word.endsWith('es') && word.length > 3) out.add(word.slice(0, -2));
  if (word.endsWith('s') && word.length > 2) out.add(word.slice(0, -1));
  out.add(`${word}s`);
  out.add(`${word}es`);
  return [...out];
}

/** Every spelling of a phrase we are willing to treat as the same phrase. */
export function keys(phrase) {
  const words = tokens(phrase);
  if (words.length === 0) return [];
  const last = words[words.length - 1];
  const head = words.slice(0, -1);
  return variants(last).map((ending) => [...head, ending].join(' '));
}

/** Drops descriptor words, which is what "normalized" means as a reason. */
export const withoutDescriptors = (phrase) =>
  tokens(phrase).filter((word) => !DESCRIPTORS.has(word)).join(' ');

export function buildIndex(items) {
  const index = new Map();
  for (const item of items) {
    for (const phrase of [item.name, ...(item.aliases ?? [])]) {
      for (const key of keys(phrase)) {
        if (!index.has(key)) index.set(key, { item, viaAlias: phrase !== item.name });
      }
    }
  }
  return index;
}

/**
 * The containment rule, mirrored so a fuzzy case can be checked.
 *
 * Every word of the canonical name must appear in the ingredient, and the two
 * must end on the same word. Without the head noun check, "milk chocolate"
 * resolves to milk.
 */
export function containmentMatches(input, canonicalName) {
  const inputWords = tokens(input);
  const nameWords = tokens(canonicalName);
  if (nameWords.length === 0 || inputWords.length === 0) return false;

  const inputSet = new Set(inputWords.flatMap(variants));
  const covered = nameWords.every((word) => variants(word).some((form) => inputSet.has(form)));
  if (!covered) return false;

  const inputLast = new Set(variants(inputWords[inputWords.length - 1]));
  return variants(nameWords[nameWords.length - 1]).some((form) => inputLast.has(form));
}

export function lintMatchingFixtures(doc, canonical) {
  const problems = [];
  const fail = (message) => problems.push(message);

  if (doc?.format !== 'canonical-matching-fixtures') {
    fail(`format should be "canonical-matching-fixtures", got ${JSON.stringify(doc?.format)}`);
  }

  const items = canonical?.items ?? [];
  const byName = new Map(items.map((item) => [normalize(item.name), item]));
  const index = buildIndex(items);

  const cases = doc?.cases;
  if (!Array.isArray(cases) || cases.length === 0) {
    fail('cases should be a non-empty array');
    return problems;
  }

  const seen = new Set();
  for (const entry of cases) {
    const where = `"${entry?.input ?? ''}"`;
    if (typeof entry?.input !== 'string') {
      fail('a case has no input');
      continue;
    }
    if (seen.has(entry.input)) fail(`${where}: the same input appears twice`);
    seen.add(entry.input);

    if (!REASONS.includes(entry.reason)) fail(`${where}: reason should be one of ${REASONS.join(', ')}`);
    if (!CONFIDENCE.includes(entry.confidence)) fail(`${where}: confidence should be one of ${CONFIDENCE.join(', ')}`);

    // An unmatched line goes to other, per section 5.3.
    if (entry.item === null) {
      if (entry.reason !== 'none') fail(`${where}: no item, so the reason should be "none"`);
      if (entry.aisle !== 'other') fail(`${where}: an unmatched ingredient belongs in aisle other, not ${entry.aisle}`);
      const hit = index.get(normalize(entry.input)) ?? index.get(withoutDescriptors(entry.input));
      if (hit) fail(`${where}: expects no match, but it resolves to "${hit.item.name}"`);
      const contained = items.filter((item) => containmentMatches(entry.input, item.name));
      if (contained.length > 0) {
        fail(`${where}: expects no match, but containment finds ${contained.map((i) => `"${i.name}"`).join(', ')}`);
      }
      continue;
    }

    const item = byName.get(normalize(entry.item));
    if (!item) {
      fail(`${where}: "${entry.item}" is not an item in canonical_items.json`);
      continue;
    }
    if (item.aisle !== entry.aisle) {
      fail(`${where}: "${entry.item}" is in aisle ${item.aisle}, not ${entry.aisle}`);
    }

    // The stated reason has to be the reason it actually matches.
    const normalizedInput = normalize(entry.input);
    const aliasKeys = new Set((item.aliases ?? []).flatMap(keys));
    const nameKeys = new Set(keys(item.name));

    switch (entry.reason) {
      case 'exactName':
        if (!nameKeys.has(normalizedInput) || normalizedInput !== normalize(item.name)) {
          fail(`${where}: claims exactName, but it is not "${item.name}" spelled out`);
        }
        break;
      case 'alias':
        if (!aliasKeys.has(normalizedInput)) {
          fail(`${where}: claims alias, but it is not one of ${JSON.stringify(item.aliases ?? [])}`);
        }
        break;
      case 'normalized': {
        const stripped = withoutDescriptors(entry.input);
        const reachable = nameKeys.has(stripped) || aliasKeys.has(stripped) || nameKeys.has(normalizedInput);
        if (!reachable) fail(`${where}: claims normalized, but dropping descriptors gives "${stripped}", which matches nothing on "${item.name}"`);
        if (aliasKeys.has(normalizedInput) || normalizedInput === normalize(item.name)) {
          fail(`${where}: claims normalized, but it already matches exactly, so the reason is wrong`);
        }
        break;
      }
      case 'contained':
        if (!containmentMatches(entry.input, item.name)) {
          fail(`${where}: claims containment with "${item.name}", but the words or the head noun do not line up`);
        }
        if (aliasKeys.has(normalizedInput) || nameKeys.has(normalizedInput)) {
          fail(`${where}: claims containment, but it matches exactly, so the reason is wrong`);
        }
        break;
      default:
        break;
    }
  }

  for (const entry of doc?.learnedAliases ?? []) {
    const item = byName.get(normalize(entry?.item));
    if (!item) fail(`learned alias "${entry?.input}": "${entry?.item}" is not an item in canonical_items.json`);
    else if (item.aisle !== entry.aisle) fail(`learned alias "${entry.input}": "${entry.item}" is in aisle ${item.aisle}`);
    if (index.get(normalize(entry?.input))) {
      fail(`learned alias "${entry?.input}": it already matches, so it teaches nothing`);
    }
  }

  const has = (predicate, label) => {
    if (!cases.some(predicate)) fail(`the corpus no longer covers ${label}`);
  };
  for (const reason of REASONS) has((c) => c.reason === reason, `the "${reason}" rung of the ladder`);
  has((c) => c.item === null, 'an ingredient that resolves to nothing');
  has((c) => /[A-Z]/.test(c.input), 'mixed case input');

  return problems;
}

/**
 * Resolves a name the way CanonicalMatcher does, for checking the seed library.
 * Kept small and in one place so there is one mirror of the rules, not two.
 */
export function resolve(name, items, index) {
  const normalized = normalize(name);
  if (!normalized) return null;
  if (index.has(normalized)) return index.get(normalized).item;

  const stripped = withoutDescriptors(name);
  if (stripped && stripped !== normalized && index.has(stripped)) return index.get(stripped).item;

  const inputWords = tokens(name);
  let best = null;
  let bestWords = 0;
  let bestExtra = Infinity;
  for (const item of items) {
    if (!containmentMatches(name, item.name)) continue;
    const nameWords = tokens(item.name).length;
    const extra = inputWords.length - nameWords;
    if (nameWords > bestWords || (nameWords === bestWords && extra < bestExtra)) {
      best = item;
      bestWords = nameWords;
      bestExtra = extra;
    }
  }
  return best;
}

/**
 * Section 5.1: every seed recipe must have canonical item links set so the list
 * generator works out of the box. This is that requirement, enforced where it
 * can run without Xcode, so editing either JSON file cannot quietly break it.
 */
export function lintSeedResolution(seed, canonical) {
  const problems = [];
  const items = canonical?.items ?? [];
  const index = buildIndex(items);

  for (const recipe of seed?.recipes ?? []) {
    for (const ingredient of recipe.ingredients ?? []) {
      const expected = ingredient.canonicalItem;
      if (!expected) {
        problems.push(`${recipe.title}: "${ingredient.name}" has no canonicalItem`);
        continue;
      }
      // The matcher sees what the parser produced: the name without its
      // trailing preparation.
      const name = String(ingredient.name ?? '').split(',')[0].trim();
      const got = resolve(name, items, index);
      if (!got) problems.push(`${recipe.title}: "${name}" resolves to nothing, but the seed says "${expected}"`);
      else if (normalize(got.name) !== normalize(expected)) {
        problems.push(`${recipe.title}: "${name}" resolves to "${got.name}", but the seed says "${expected}"`);
      }
    }
  }

  return problems;
}
