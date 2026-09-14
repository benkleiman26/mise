#!/usr/bin/env node
// Turns a localStorage dump from collect-localstorage.js into the same
// <out>/raw/recipes layout that the API export produces, so that
// `npm run normalize` works identically on either rescue path.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import path from 'node:path';

/** Splits a dump into recipe records keyed by the uuid in the localStorage key. */
export function recipesFromDump(dump) {
  const out = [];
  for (const [key, value] of Object.entries(dump?.entries ?? {})) {
    const match = key.match(/mealime\/recipes\/([^/]+)$/i);
    if (!match) continue;
    let body;
    try {
      body = typeof value === 'string' ? JSON.parse(value) : value;
    } catch {
      out.push({ id: match[1], body: null, error: 'value was not JSON' });
      continue;
    }
    out.push({ id: match[1], body });
  }
  return out;
}

async function main() {
  const { values } = parseArgs({
    options: { in: { type: 'string' }, out: { type: 'string' } },
  });
  if (!values.in) {
    console.error('Usage: node browser/convert.mjs --in <dump.json> [--out <dir>]');
    process.exit(2);
  }
  const outDir = path.resolve(
    values.out ?? path.join(import.meta.dirname, '..', '..', '..', 'data', 'mealime')
  );
  const dump = JSON.parse(await readFile(path.resolve(values.in), 'utf8'));
  const recipes = recipesFromDump(dump);

  const recipeDir = path.join(outDir, 'raw', 'recipes');
  await mkdir(recipeDir, { recursive: true });
  let written = 0;
  const failed = [];
  for (const { id, body, error } of recipes) {
    if (error || body === null) {
      failed.push({ id, error });
      continue;
    }
    await writeFile(
      path.join(recipeDir, `${encodeURIComponent(id)}.json`),
      JSON.stringify(body, null, 2) + '\n',
      'utf8'
    );
    written += 1;
  }

  // Keep the whole dump too. Sibling keys may hold the grocery list and
  // favorites, and we would rather keep them than discover the gap in November.
  await mkdir(path.join(outDir, 'raw'), { recursive: true });
  await writeFile(
    path.join(outDir, 'raw', 'localstorage-dump.json'),
    JSON.stringify(dump, null, 2) + '\n',
    'utf8'
  );

  console.log(`Wrote ${written} recipes to ${recipeDir}`);
  if (failed.length) console.log(`${failed.length} entries could not be parsed: ${failed.map((f) => f.id).join(', ')}`);
  console.log('Next: npm run normalize');
}

if (process.argv[1] && import.meta.url.endsWith(path.basename(process.argv[1]))) {
  main().catch((error) => {
    console.error(`Failed: ${error.message}`);
    process.exit(1);
  });
}
