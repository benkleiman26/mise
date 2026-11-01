#!/usr/bin/env node
// Lints Mise/Resources against the rules in the spec. Run it before committing
// a change to those files.

import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

import { lintCanonicalItems, lintSeedRecipes } from './lint.mjs';
import { lintUnitFixtures } from './units.mjs';
import { lintIngredientFixtures } from './ingredients.mjs';
import { lintMatchingFixtures, lintSeedResolution } from './matching.mjs';
import { lintListFixtures } from './list.mjs';

const root = path.join(import.meta.dirname, '..', '..', '..', 'Mise', 'Resources');
const canonicalFile = path.join(root, 'canonical_items.json');
const seedFile = path.join(root, 'seed_recipes.json');

async function readJson(file) {
  return JSON.parse(await readFile(file, 'utf8'));
}

let failures = 0;

const canonical = await readJson(canonicalFile);
const canonicalProblems = lintCanonicalItems(canonical);
console.log(`canonical_items.json: ${canonical.items.length} items, ${canonical.items.filter((i) => i.isStaple).length} staples`);
for (const problem of canonicalProblems) console.error(`  ${problem}`);
failures += canonicalProblems.length;

if (existsSync(seedFile)) {
  const seed = await readJson(seedFile);
  const seedProblems = lintSeedRecipes(seed, canonical);
  console.log(`seed_recipes.json: ${seed.recipes?.length ?? 0} recipes`);
  for (const problem of seedProblems) console.error(`  ${problem}`);
  failures += seedProblems.length;
} else {
  console.log('seed_recipes.json: not present yet');
}

const unitFixtures = path.join(import.meta.dirname, '..', '..', '..', 'MiseTests', 'Fixtures', 'unit_conversion.json');
if (existsSync(unitFixtures)) {
  const doc = await readJson(unitFixtures);
  const problems = lintUnitFixtures(doc);
  console.log(
    `unit_conversion.json: ${doc.conversions?.length ?? 0} conversions, ` +
      `${doc.combinations?.length ?? 0} combinations, ${doc.fractions?.length ?? 0} fractions`
  );
  for (const problem of problems) console.error(`  ${problem}`);
  failures += problems.length;
} else {
  console.log('unit_conversion.json: not present yet');
}

const ingredientFixtures = path.join(import.meta.dirname, '..', '..', '..', 'MiseTests', 'Fixtures', 'ingredient_parsing.json');
if (existsSync(ingredientFixtures)) {
  const doc = await readJson(ingredientFixtures);
  const problems = lintIngredientFixtures(doc);
  console.log(`ingredient_parsing.json: ${doc.cases?.length ?? 0} cases`);
  for (const problem of problems) console.error(`  ${problem}`);
  failures += problems.length;
} else {
  console.log('ingredient_parsing.json: not present yet');
}

if (existsSync(seedFile)) {
  const seed = await readJson(seedFile);
  const problems = lintSeedResolution(seed, canonical);
  const lines = seed.recipes.reduce((n, r) => n + (r.ingredients?.length ?? 0), 0);
  console.log(`seed ingredient resolution: ${lines - problems.length} of ${lines} lines resolve to the item the seed names`);
  for (const problem of problems) console.error(`  ${problem}`);
  failures += problems.length;
}

const matchingFixtures = path.join(import.meta.dirname, '..', '..', '..', 'MiseTests', 'Fixtures', 'canonical_matching.json');
if (existsSync(matchingFixtures)) {
  const doc = await readJson(matchingFixtures);
  const problems = lintMatchingFixtures(doc, canonical);
  console.log(`canonical_matching.json: ${doc.cases?.length ?? 0} cases, ${doc.learnedAliases?.length ?? 0} learned aliases`);
  for (const problem of problems) console.error(`  ${problem}`);
  failures += problems.length;
} else {
  console.log('canonical_matching.json: not present yet');
}

const listFixtures = path.join(import.meta.dirname, '..', '..', '..', 'MiseTests', 'Fixtures', 'list_generation.json');
if (existsSync(listFixtures) && existsSync(seedFile)) {
  const doc = await readJson(listFixtures);
  const seed = await readJson(seedFile);
  const problems = lintListFixtures(doc, seed, canonical);
  console.log(`list_generation.json: ${doc.scenarios?.length ?? 0} scenarios`);
  for (const problem of problems) console.error(`  ${problem}`);
  failures += problems.length;
} else {
  console.log('list_generation.json: not present yet');
}

if (failures) {
  console.error(`\n${failures} problem${failures === 1 ? '' : 's'}.`);
  process.exit(1);
}
console.log('\nAll good.');
