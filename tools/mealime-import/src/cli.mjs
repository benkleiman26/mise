#!/usr/bin/env node
// Read the rescued Mealime library and write one file Mise can import.
//
//   node src/cli.mjs
//   node src/cli.mjs --in ../../data/mealime/recipes --out ../../data/mise/mealime_import.json
//
// Reads only. It never touches the rescued files, which since Mealime shut down
// on 2026-10-21 are the only copy in existence.

import { readdir, readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { convertLibrary } from './convert.mjs';
import { attachPhotos } from './images.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..', '..');

function option(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const inDir = resolve(option('--in', join(repoRoot, 'data', 'mealime', 'recipes')));
const outFile = resolve(option('--out', join(repoRoot, 'data', 'mise', 'mealime_import.json')));
const servings = Number(option('--default-servings', '4')) || 4;

let names;
try {
  names = (await readdir(inDir)).filter((n) => n.endsWith('.json')).sort();
} catch (error) {
  console.error(`Could not read ${inDir}`);
  console.error(`  ${error.message}`);
  console.error('\nIf the rescued recipes are somewhere else, pass --in <folder>.');
  process.exit(1);
}

if (names.length === 0) {
  console.error(`No .json files in ${inDir}. Nothing to convert.`);
  process.exit(1);
}

const sources = [];
const unreadable = [];
for (const name of names) {
  try {
    sources.push({ file: name, recipe: JSON.parse(await readFile(join(inDir, name), 'utf8')) });
  } catch (error) {
    unreadable.push({ file: name, why: error.message });
  }
}

const { document, report } = convertLibrary(sources, { defaultServings: servings });

// The rescued photos, one per recipe, copied next to the import file so the
// app can read them from alongside it. --no-photos skips the whole thing.
let photos = null;
if (!process.argv.includes('--no-photos')) {
  const imagesDir = resolve(option('--images', join(repoRoot, 'data', 'mealime', 'images')));
  photos = await attachPhotos(document.recipes, { imagesDir, outDir: dirname(outFile) });
}

await mkdir(dirname(outFile), { recursive: true });
await writeFile(outFile, `${JSON.stringify(document, null, 2)}\n`, 'utf8');

console.log(`Read ${report.read} files from ${inDir}`);
console.log(`Converted ${report.converted} recipes, ${report.ingredientLines} ingredient lines`);
if (report.withoutCookTime) console.log(`  ${report.withoutCookTime} have no cooking time recorded`);
if (report.withoutSteps) console.log(`  ${report.withoutSteps} have no steps`);
if (report.withoutIngredients) console.log(`  ${report.withoutIngredients} have no ingredients`);
if (report.junkDropped) console.log(`  ${report.junkDropped} page furniture lines dropped`);

for (const { file, why } of [...unreadable, ...report.skipped]) {
  console.log(`  skipped ${file}: ${why}`);
}

if (photos) {
  const mb = (photos.bytes / 1024 / 1024).toFixed(1);
  console.log(`Photos: ${photos.copied} copied (${mb} MB), ${photos.missing} recipes have none`);
}

console.log(`\nWrote ${outFile}`);
console.log('That file stays on this machine. It is inside data/, which git ignores.');
