#!/usr/bin/env node
// Lints Mise/Resources against the rules in the spec. Run it before committing
// a change to those files.

import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

import { lintCanonicalItems, lintSeedRecipes } from './lint.mjs';

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

if (failures) {
  console.error(`\n${failures} problem${failures === 1 ? '' : 's'}.`);
  process.exit(1);
}
console.log('\nAll good.');
