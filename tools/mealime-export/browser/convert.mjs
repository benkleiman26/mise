#!/usr/bin/env node
// Turns a localStorage dump from collect-localstorage.js into the same
// <out>/raw/recipes layout that the API export produces, so that
// `npm run normalize` works identically on either rescue path.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { parseArgs } from 'node:util';
import path from 'node:path';

/**
 * Reads either browser dump format.
 *
 * `mealime-rescue` comes from rescue.js, which fetches each recipe from
 * cdn-recipes.mealime.com and keys them by uuid directly. `localstorage-dump`
 * comes from collect-localstorage.js, which reads the web app's own cache and
 * keys them by the full localStorage key.
 */
export function recipesFromDump(dump) {
  if (dump?.format === 'mealime-rescue') return recipesFromRescue(dump);
  return recipesFromLocalStorage(dump);
}

/** rescue.js output: recipes already parsed and keyed by uuid. */
export function recipesFromRescue(dump) {
  return Object.entries(dump?.recipes ?? {}).map(([id, body]) => ({ id, body }));
}

/**
 * Works out which recipes were seen on which page, so a favorites page scan
 * becomes a favorites list. Returns a map of page path to the ids found there.
 */
export function idsByPage(dump) {
  const pages = {};
  for (const [id, entry] of Object.entries(dump?.sources ?? {})) {
    for (const source of entry.sources ?? []) {
      (pages[source] ??= []).push(id);
    }
  }
  return pages;
}

/** collect-localstorage.js output: values are JSON strings under prefixed keys. */
export function recipesFromLocalStorage(dump) {
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
  console.log(`Reading a ${dump?.format ?? 'localstorage'} dump with ${recipes.length} recipes`);

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

  // Keep the whole dump too. It carries the page text and the id to page map,
  // which is where favorites and the grocery list have to come from, and we
  // would rather keep them than discover the gap in November.
  await mkdir(path.join(outDir, 'raw'), { recursive: true });
  const dumpName = dump?.format === 'mealime-rescue' ? 'mealime-rescue.json' : 'localstorage-dump.json';
  await writeFile(path.join(outDir, 'raw', dumpName), JSON.stringify(dump, null, 2) + '\n', 'utf8');

  // Record where each recipe was seen, so normalize can tell a favorite from a
  // plain library recipe the same way the API path did.
  const pages = idsByPage(dump);
  await writeFile(
    path.join(outDir, 'raw', '_recipe_index.json'),
    JSON.stringify(
      recipes.map(({ id }) => ({
        id,
        roles: Object.entries(pages)
          .filter(([, ids]) => ids.includes(id))
          .map(([page]) => (/favorit/i.test(page) ? 'favorites' : /recipe/i.test(page) ? 'userRecipes' : page)),
        summary: {},
      })),
      null,
      2
    ) + '\n',
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
