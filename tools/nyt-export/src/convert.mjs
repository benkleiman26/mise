// Turns the browser dump into data/nyt/nyt_recipe_box.json, the file the app's
// bulk NYT import reads.
//
// Pure functions, no network. The app fetches each recipe page itself and runs
// it through the JSON-LD pipeline (spec section 5.6a), so this file only needs
// to carry what the app cannot work out on its own: which folder a recipe was
// in, and whether it is in the Cooked Recipes list.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

export const RECIPE_URL = /^https:\/\/cooking\.nytimes\.com\/recipes?\/(\d+)(?:-([a-z0-9-]+))?/i;

/** Folders that describe a status rather than a topic, so never become tags. */
export const STATUS_FOLDERS = [
  /^cooked/i,
  /^recipe box$/i,
  /^my recipes?$/i,
  /^saved/i,
  /^all\b/i,
  /^recently/i,
  // A folder url is a numeric id, so a name that is only digits means the
  // folder's real name was never captured. Better no tag than a tag called
  // "38271228".
  /^\d+$/,
];

/**
 * Turns a folder name into a tag. Spec section 5.1 wants tags flat and
 * lowercase, and section 5.6a wants Recipe Box folders mapped to tags, for
 * example "Easy Kid-Friendly Recipes" to "kid friendly".
 */
export function folderToTag(name) {
  if (typeof name !== 'string') return null;
  const trimmed = name.trim();
  if (!trimmed || STATUS_FOLDERS.some((pattern) => pattern.test(trimmed))) return null;
  const tag = trimmed
    .toLowerCase()
    .replace(/[_/]+/g, ' ')
    .replace(/\brecipes?\b/g, '')
    .replace(/\beasy\b/g, '')
    .replace(/[^a-z0-9- ]+/g, '')
    .replace(/-/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  return tag.length >= 3 ? tag : null;
}

/**
 * Validates and tidies one harvested record. Returns null for anything that is
 * not a real recipe, since the harvest deliberately over-collects.
 */
export function normalizeRecipe(record) {
  if (!record || typeof record !== 'object') return null;
  const id = String(record.id ?? '').trim();
  if (!/^\d+$/.test(id)) return null;

  let url = typeof record.url === 'string' ? record.url.trim() : '';
  if (!RECIPE_URL.test(url)) {
    // A slug is optional in NYT's own links, and the canonical form redirects
    // correctly with just the id.
    url = record.slug
      ? `https://cooking.nytimes.com/recipes/${id}-${record.slug}`
      : `https://cooking.nytimes.com/recipes/${id}`;
  }

  const folders = [...new Set((record.folders ?? []).filter((f) => typeof f === 'string' && f.trim()))].map((f) => f.trim());
  const tags = [...new Set(folders.map(folderToTag).filter(Boolean))];

  return {
    id,
    url,
    title: typeof record.title === 'string' && record.title.trim() ? record.title.trim() : null,
    author: typeof record.author === 'string' && record.author.trim() ? record.author.trim() : null,
    image: typeof record.image === 'string' && record.image.startsWith('http') ? record.image : null,
    folders,
    tags,
    cooked: Boolean(record.cooked),
    // The app fetches every one of these anyway, so a record with no title is
    // still perfectly usable. This just flags how thin the harvest was.
    titleFromHarvest: Boolean(record.title),
  };
}

/** Builds the export file from a raw browser dump. */
export function buildRecipeBox(dump, { now = () => new Date().toISOString() } = {}) {
  const records = Array.isArray(dump?.recipes) ? dump.recipes : Object.values(dump?.recipes ?? {});
  const byId = new Map();
  const rejected = [];

  for (const record of records) {
    const normalized = normalizeRecipe(record);
    if (!normalized) {
      rejected.push({ id: record?.id ?? null, url: record?.url ?? null, reason: 'not a recipe id' });
      continue;
    }
    const existing = byId.get(normalized.id);
    if (!existing) {
      byId.set(normalized.id, normalized);
      continue;
    }
    // The same recipe seen in two folders keeps both.
    byId.set(normalized.id, {
      ...existing,
      title: existing.title ?? normalized.title,
      author: existing.author ?? normalized.author,
      image: existing.image ?? normalized.image,
      folders: [...new Set([...existing.folders, ...normalized.folders])],
      tags: [...new Set([...existing.tags, ...normalized.tags])],
      cooked: existing.cooked || normalized.cooked,
    });
  }

  const recipes = [...byId.values()].sort((a, b) => Number(a.id) - Number(b.id));
  const folderCounts = {};
  for (const recipe of recipes) {
    for (const folder of recipe.folders) folderCounts[folder] = (folderCounts[folder] ?? 0) + 1;
  }

  return {
    format: 'nyt-recipe-box',
    version: 1,
    exportedAt: now(),
    source: { collectedAt: dump?.collectedAt ?? null, pagesScanned: Object.keys(dump?.pages ?? {}).length },
    counts: {
      recipes: recipes.length,
      cooked: recipes.filter((r) => r.cooked).length,
      withTitle: recipes.filter((r) => r.title).length,
      folders: Object.keys(folderCounts).length,
      rejected: rejected.length,
    },
    folders: Object.entries(folderCounts)
      .map(([name, count]) => ({ name, count, tag: folderToTag(name) }))
      .sort((a, b) => b.count - a.count),
    recipes,
    rejected,
  };
}

/** Warnings worth showing before the owner walks away thinking it is done. */
export function reviewWarnings(box, { expected = 163 } = {}) {
  const warnings = [];
  const { recipes, cooked, withTitle } = box.counts;
  if (recipes < expected * 0.9) {
    warnings.push(
      `Only ${recipes} recipes, and about ${expected} were expected. Open each folder in the browser and run __nyt.scan() there, since a fetched page can miss lazily loaded rows.`
    );
  }
  if (cooked === 0) {
    warnings.push('Nothing is marked cooked. The Cooked Recipes list was probably never scanned.');
  }
  if (withTitle < recipes * 0.5) {
    warnings.push(
      `Only ${withTitle} of ${recipes} have titles, so most came from raw link matching. Harmless, since the app fetches each page, but it means the page structure was not recognized.`
    );
  }
  if (box.counts.folders <= 1) {
    warnings.push('Only one folder was seen. Folder to tag mapping will be thin.');
  }
  return warnings;
}

export async function runConvert({ inFile, outFile, log = console.log }) {
  const dump = JSON.parse(await readFile(inFile, 'utf8'));
  if (dump?.format && dump.format !== 'nyt-recipe-box-raw') {
    log(`Warning: expected a nyt-recipe-box-raw dump, got "${dump.format}". Continuing anyway.`);
  }
  const box = buildRecipeBox(dump);

  await mkdir(path.dirname(outFile), { recursive: true });
  await writeFile(outFile, JSON.stringify(box, null, 2) + '\n', 'utf8');

  log(`Wrote ${outFile}`);
  log(`  recipes: ${box.counts.recipes}`);
  log(`  cooked: ${box.counts.cooked}`);
  log(`  folders: ${box.counts.folders}`);
  if (box.counts.rejected) log(`  ignored (not recipes): ${box.counts.rejected}`);
  for (const folder of box.folders) {
    log(`    ${folder.name}: ${folder.count}${folder.tag ? ` -> tag "${folder.tag}"` : ''}`);
  }
  const warnings = reviewWarnings(box);
  if (warnings.length) {
    log('');
    for (const warning of warnings) log(`Warning: ${warning}`);
  }
  return box;
}
