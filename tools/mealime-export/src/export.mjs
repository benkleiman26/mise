// Stage 1 of the rescue: pull everything down and write it to disk exactly as
// the server sent it.
//
// Nothing is reshaped here on purpose. Mealime deletes all account data on
// 2026-10-21. If our assumptions about the JSON turn out to be wrong we can fix
// the normalizer afterwards and re-run it against these files, but we cannot
// re-fetch. Raw first, parse later.

import { mkdir, readdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

import { ReadOnlyClient } from './http.mjs';
import {
  DEFAULT_BASE,
  extractCollection,
  nextPage,
  probeCollections,
  probeSingletons,
  resolveAuthScheme,
} from './discover.mjs';

export const RECIPE_ID_KEYS = ['uuid', 'id', 'recipe_id', 'recipe_uuid', 'slug'];

/** Reads the identifier off a recipe summary, preferring stable keys. */
export function recipeId(record) {
  if (!record || typeof record !== 'object') return null;
  for (const key of RECIPE_ID_KEYS) {
    const value = record[key];
    if (typeof value === 'string' && value) return value;
    if (typeof value === 'number' && Number.isFinite(value)) return String(value);
  }
  return null;
}

/** Picks the probe result most likely to be the real collection for a role. */
export function chooseCandidate(probes) {
  const usable = probes.filter((p) => p.ok && p.count !== null);
  if (usable.length === 0) return null;
  return usable.sort((a, b) => b.count - a.count)[0];
}

async function writeJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

/** Walks every page of a collection endpoint, saving each page verbatim. */
async function fetchAllPages({ client, url, role, rawDir, log }) {
  const pages = [];
  const records = [];
  let current = url;
  let index = 0;
  while (current && index < 200) {
    const response = await client.get(current);
    if (response.status !== 200 || response.json === null) {
      log(`  ${role}: stopped at page ${index} with HTTP ${response.status}`);
      break;
    }
    await writeJson(path.join(rawDir, 'collections', `${role}.page-${index}.json`), response.json);
    pages.push({ url: current, status: response.status });
    const collection = extractCollection(response.json) ?? [];
    records.push(...collection);
    log(`  ${role}: page ${index} gave ${collection.length} records`);
    current = nextPage(response.json, current);
    index += 1;
  }
  return { pages, records };
}

/**
 * Runs the full export.
 *
 * @param {object} options
 * @param {string} options.token
 * @param {string} options.outDir   Where to write, normally data/mealime.
 * @param {string} [options.base]
 * @param {string} [options.scheme] Skip auth detection when already known.
 * @param {boolean} [options.force] Re-fetch recipes already on disk.
 * @param {number} [options.limit]  Stop after N recipe detail fetches, for a smoke test.
 */
export async function runExport({ token, outDir, base = DEFAULT_BASE, scheme, force = false, limit = Infinity, log = console.log }) {
  const rawDir = path.join(outDir, 'raw');
  await mkdir(rawDir, { recursive: true });

  log('Resolving auth scheme');
  let identity = null;
  let resolvedScheme = scheme;
  if (!resolvedScheme) {
    const resolved = await resolveAuthScheme({ token, base, log });
    if (!resolved.ok) throw new Error(resolved.diagnosis);
    resolvedScheme = resolved.scheme;
    identity = resolved.identity;
    log(`Auth scheme: ${resolvedScheme} via ${resolved.identityPath}`);
  }

  const client = new ReadOnlyClient({ token, scheme: resolvedScheme, log: (m) => log(`  ${m}`) });
  if (identity) await writeJson(path.join(rawDir, 'identity.json'), identity);

  log('Probing singleton endpoints');
  const singletons = await probeSingletons({ client, base, log });
  for (const [role, { path: found, body }] of Object.entries(singletons)) {
    log(`${role}: using ${found}`);
    await writeJson(path.join(rawDir, `${role}.json`), body);
  }

  log('Probing collection endpoints');
  const probes = await probeCollections({ client, base, log });
  await writeJson(path.join(rawDir, '_discovery.json'), { base, scheme: resolvedScheme, probes });

  const chosen = {};
  const collections = {};
  for (const [role, results] of Object.entries(probes)) {
    const candidate = chooseCandidate(results);
    if (!candidate) {
      log(`  ${role}: no usable endpoint, skipping`);
      continue;
    }
    chosen[role] = candidate.path;
    log(`${role}: using ${candidate.path}`);
    collections[role] = await fetchAllPages({ client, url: base + candidate.path, role, rawDir, log });
  }

  // Every recipe we can see, from any collection, deduplicated by id.
  const wanted = new Map();
  for (const role of ['favorites', 'userRecipes']) {
    for (const record of collections[role]?.records ?? []) {
      const id = recipeId(record);
      if (id && !wanted.has(id)) wanted.set(id, { id, roles: [role], summary: record });
      else if (id) wanted.get(id).roles.push(role);
    }
  }
  log(`Found ${wanted.size} distinct recipes across collections`);

  // The collection a recipe came from is the strongest signal of who wrote it,
  // and that decides whether the public export may carry its full text. Save it
  // now, because the collection pages are only fetched once.
  await writeJson(path.join(rawDir, '_recipe_index.json'), [...wanted.values()]);

  const recipeDir = path.join(rawDir, 'recipes');
  await mkdir(recipeDir, { recursive: true });
  const fetched = [];
  const failed = [];
  let count = 0;
  for (const { id, summary } of wanted.values()) {
    if (count >= limit) break;
    const file = path.join(recipeDir, `${encodeURIComponent(id)}.json`);
    if (!force && existsSync(file)) {
      fetched.push(id);
      continue;
    }
    const response = await client.get(`${base}/recipes/${encodeURIComponent(id)}`);
    if (response.status === 200 && response.json !== null) {
      await writeJson(file, response.json);
      fetched.push(id);
    } else {
      // Keep the collection summary even when the detail fetch fails. A partial
      // record beats nothing once the account is gone.
      await writeJson(path.join(rawDir, 'recipes-partial', `${encodeURIComponent(id)}.json`), summary);
      failed.push({ id, status: response.status });
      log(`  recipe ${id}: HTTP ${response.status}, kept the summary only`);
    }
    count += 1;
    if (count % 10 === 0) log(`  fetched ${count} of ${Math.min(wanted.size, limit)}`);
  }

  const manifest = {
    exportedAt: new Date().toISOString(),
    base,
    scheme: resolvedScheme,
    endpoints: chosen,
    counts: {
      favorites: collections.favorites?.records.length ?? 0,
      userRecipes: collections.userRecipes?.records.length ?? 0,
      distinctRecipes: wanted.size,
      recipeDetailsOnDisk: fetched.length,
      recipeDetailsFailed: failed.length,
      preferences: Object.keys(singletons).length,
      mealPlans: collections.mealPlans?.records.length ?? 0,
      groceryLists: collections.groceryLists?.records.length ?? 0,
    },
    failed,
    requestCount: client.requestCount,
  };
  await writeJson(path.join(rawDir, '_manifest.json'), manifest);

  log('');
  log('Export complete. Counts:');
  for (const [key, value] of Object.entries(manifest.counts)) log(`  ${key}: ${value}`);
  log('');
  log('Check these against what my.mealime.com shows, roughly 30 favorites and');
  log('roughly 150 of your own recipes. If they do not match, re-run before the');
  log('2026-10-21 deletion date rather than trying to fix it afterwards.');
  return manifest;
}

/** Lists the recipe ids already rescued, used by the resume path and by tests. */
export async function existingRecipeIds(rawDir) {
  const dir = path.join(rawDir, 'recipes');
  if (!existsSync(dir)) return [];
  const files = await readdir(dir);
  return files.filter((f) => f.endsWith('.json')).map((f) => decodeURIComponent(f.replace(/\.json$/, '')));
}
