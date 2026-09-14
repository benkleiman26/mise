// Takes a bookmarks export apart and says what is actually in it, so Phase 4
// can be planned against real numbers rather than a guess.
//
// The questions it answers: how many URLs are there, how many are already in
// the NYT Recipe Box export, which hosts dominate, and how many are not recipes
// at all. That decides how much work the AI extraction fallback has to do,
// which is the expensive path in spec section 5.6a.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

import { canonicalUrl, looksLikeRecipe, nytRecipeId, parseBookmarks } from './bookmarks.mjs';

/** Builds the inventory. `knownNytIds` comes from nyt_recipe_box.json. */
export function buildInventory({ html, knownNytIds = new Set(), folderFilter = null, now = () => new Date().toISOString() }) {
  const { bookmarks, folders } = parseBookmarks(html);
  const selected = folderFilter
    ? bookmarks.filter((b) => (b.folder ?? '').toLowerCase().includes(folderFilter.toLowerCase()))
    : bookmarks;

  const byCanonical = new Map();
  let duplicates = 0;
  for (const bookmark of selected) {
    const key = canonicalUrl(bookmark.url);
    if (byCanonical.has(key)) {
      duplicates += 1;
      const existing = byCanonical.get(key);
      existing.folders = [...new Set([...existing.folders, bookmark.folder].filter(Boolean))];
      continue;
    }
    byCanonical.set(key, {
      url: key,
      originalUrl: bookmark.url,
      title: bookmark.title,
      folders: [bookmark.folder].filter(Boolean),
      addedAt: bookmark.addedAt,
      host: hostOf(key),
      nytRecipeId: nytRecipeId(bookmark.url),
      likelyRecipe: looksLikeRecipe(bookmark),
    });
  }

  const entries = [...byCanonical.values()];
  for (const entry of entries) {
    entry.alreadyInRecipeBox = Boolean(entry.nytRecipeId && knownNytIds.has(entry.nytRecipeId));
  }

  const byHost = {};
  for (const entry of entries) byHost[entry.host] = (byHost[entry.host] ?? 0) + 1;

  const toImport = entries.filter((e) => e.likelyRecipe && !e.alreadyInRecipeBox);

  return {
    format: 'bookmarks-inventory',
    version: 1,
    builtAt: now(),
    counts: {
      bookmarksInFile: bookmarks.length,
      selected: selected.length,
      unique: entries.length,
      duplicates,
      nytRecipes: entries.filter((e) => e.nytRecipeId).length,
      alreadyInRecipeBox: entries.filter((e) => e.alreadyInRecipeBox).length,
      likelyRecipes: entries.filter((e) => e.likelyRecipe).length,
      notRecipes: entries.filter((e) => !e.likelyRecipe).length,
      toImport: toImport.length,
    },
    folders,
    hosts: Object.entries(byHost)
      .map(([host, count]) => ({ host, count }))
      .sort((a, b) => b.count - a.count),
    entries,
  };
}

function hostOf(url) {
  try {
    return new URL(url).hostname;
  } catch {
    return '(unparseable)';
  }
}

/** Reads the recipe ids already exported from the NYT Recipe Box. */
export async function knownNytIdsFrom(file) {
  if (!file || !existsSync(file)) return new Set();
  const box = JSON.parse(await readFile(file, 'utf8'));
  return new Set((box.recipes ?? []).map((r) => String(r.id)));
}

export async function runInventory({ inFile, outFile, nytFile = null, folder = null, log = console.log }) {
  const html = await readFile(inFile, 'utf8');
  const knownNytIds = await knownNytIdsFrom(nytFile);
  if (nytFile && knownNytIds.size === 0) {
    log(`Note: no NYT Recipe Box export found at ${nytFile}, so nothing can be marked as already saved.`);
  }

  const inventory = buildInventory({ html, knownNytIds, folderFilter: folder });
  await mkdir(path.dirname(outFile), { recursive: true });
  await writeFile(outFile, JSON.stringify(inventory, null, 2) + '\n', 'utf8');

  const { counts } = inventory;
  log(`Wrote ${outFile}`);
  log(`  bookmarks in file: ${counts.bookmarksInFile}`);
  if (folder) log(`  in folders matching "${folder}": ${counts.selected}`);
  log(`  unique urls: ${counts.unique} (${counts.duplicates} duplicates collapsed)`);
  log(`  look like recipes: ${counts.likelyRecipes}`);
  log(`  not recipes: ${counts.notRecipes}`);
  log(`  NYT recipes: ${counts.nytRecipes}, of which ${counts.alreadyInRecipeBox} are already in the Recipe Box export`);
  log(`  to import: ${counts.toImport}`);
  log('');
  log('Top hosts:');
  for (const { host, count } of inventory.hosts.slice(0, 12)) log(`  ${String(count).padStart(4)}  ${host}`);
  return inventory;
}
