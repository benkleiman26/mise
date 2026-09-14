// Downloads recipe images to disk.
//
// The rescued JSON references images by URL on Mealime's CDN. When the service
// shuts down on 2026-10-21 those URLs are very likely to stop resolving along
// with everything else, and a recipe with a dead image link is a worse rescue
// than one with the picture saved. So pull the bytes down while they are still
// there.
//
// This runs after `normalize` and can be re-run freely: files already on disk
// are skipped, so an interrupted download resumes.
//
// Note on auth: image hosts are third parties (Mealime's CDN, and any blog a
// user imported a recipe from), so no Authorization header is ever sent here.
// The auth token is for api.mealime.com only.

import { mkdir, readFile, readdir, stat, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

/** Cap per image. Recipe photos are well under this; anything larger is wrong. */
export const MAX_IMAGE_BYTES = 12 * 1024 * 1024;

const EXTENSION_BY_TYPE = {
  'image/jpeg': '.jpg',
  'image/jpg': '.jpg',
  'image/png': '.png',
  'image/webp': '.webp',
  'image/gif': '.gif',
  'image/avif': '.avif',
  'image/heic': '.heic',
};

/** Works out a file extension, preferring what the server said over the URL. */
export function extensionFor(contentType, url) {
  const type = String(contentType ?? '').split(';')[0].trim().toLowerCase();
  if (EXTENSION_BY_TYPE[type]) return EXTENSION_BY_TYPE[type];
  try {
    const fromUrl = path.extname(new URL(url).pathname).toLowerCase();
    if (Object.values(EXTENSION_BY_TYPE).includes(fromUrl)) return fromUrl;
    if (fromUrl === '.jpeg') return '.jpg';
  } catch {
    // Fall through to the default below.
  }
  return '.img';
}

/** Turns a recipe id into something safe to use as a directory name. */
export function safeName(id) {
  return encodeURIComponent(String(id)).replace(/[*?"<>|]/g, '_');
}

/**
 * Lists every image worth fetching across a set of recipes.
 * Withheld recipes are included: the reference keeps an image URL, and a
 * thumbnail is what makes "find me something like this" usable later.
 */
export function imageTargets(recipes = []) {
  const targets = [];
  for (const recipe of recipes) {
    const urls = recipe.images ?? (recipe.image ? [recipe.image] : []);
    urls.forEach((url, index) => {
      if (typeof url !== 'string' || !url.startsWith('http')) return;
      targets.push({ recipeId: recipe.mealime_id, url, index });
    });
  }
  return targets;
}

/** Runs tasks with a fixed number in flight. Keeps us polite to the CDN. */
export async function pool(items, limit, worker) {
  const results = new Array(items.length);
  let cursor = 0;
  const runners = Array.from({ length: Math.min(limit, items.length) }, async () => {
    for (;;) {
      const index = cursor++;
      if (index >= items.length) return;
      results[index] = await worker(items[index], index);
    }
  });
  await Promise.all(runners);
  return results;
}

/**
 * Fetches one image. Returns a result rather than throwing, because one dead
 * URL must not stop the rest of the rescue.
 */
export async function downloadOne(target, { dir, fetchImpl = fetch, force = false }) {
  const { recipeId, url, index } = target;
  const folder = path.join(dir, safeName(recipeId));

  if (!force) {
    const existing = await findExisting(folder, index);
    if (existing) return { ...target, status: 'skipped', file: existing };
  }

  let response;
  try {
    response = await fetchImpl(url, { redirect: 'follow' });
  } catch (cause) {
    return { ...target, status: 'failed', error: cause.message };
  }
  if (!response.ok) return { ...target, status: 'failed', error: `HTTP ${response.status}` };

  const buffer = Buffer.from(await response.arrayBuffer());
  if (buffer.byteLength === 0) return { ...target, status: 'failed', error: 'empty body' };
  if (buffer.byteLength > MAX_IMAGE_BYTES) {
    return { ...target, status: 'failed', error: `too large (${buffer.byteLength} bytes)` };
  }

  const extension = extensionFor(response.headers?.get?.('content-type'), url);
  const file = path.join(folder, `${index}${extension}`);
  await mkdir(folder, { recursive: true });
  await writeFile(file, buffer);
  return { ...target, status: 'downloaded', file, bytes: buffer.byteLength };
}

async function findExisting(folder, index) {
  if (!existsSync(folder)) return null;
  const files = await readdir(folder);
  const match = files.find((f) => f.startsWith(`${index}.`));
  if (!match) return null;
  const full = path.join(folder, match);
  const info = await stat(full);
  return info.size > 0 ? full : null;
}

/** Records the saved paths on a recipe, relative to the export directory. */
export function attachLocalPaths(recipes, results, outDir) {
  const byRecipe = new Map();
  for (const result of results) {
    if (result.status === 'failed') continue;
    const list = byRecipe.get(String(result.recipeId)) ?? [];
    list[result.index] = path.relative(outDir, result.file);
    byRecipe.set(String(result.recipeId), list);
  }
  return recipes.map((recipe) => {
    const local = byRecipe.get(String(recipe.mealime_id));
    if (!local) return recipe;
    return { ...recipe, local_images: local.filter(Boolean) };
  });
}

/**
 * Downloads every image referenced by mealime-export.json and records the local
 * paths in the bundle and in the per recipe files.
 */
export async function runImages({ outDir, concurrency = 4, force = false, fetchImpl = fetch, log = console.log }) {
  const bundleFile = path.join(outDir, 'mealime-export.json');
  if (!existsSync(bundleFile)) {
    throw new Error(`No ${bundleFile}. Run the export and normalize steps first.`);
  }
  const bundle = JSON.parse(await readFile(bundleFile, 'utf8'));
  const dir = path.join(outDir, 'images');

  const all = [...bundle.recipes, ...bundle.withheld];
  const targets = imageTargets(all);
  if (targets.length === 0) {
    log('No image URLs in the export, nothing to download.');
    return { downloaded: 0, skipped: 0, failed: [] };
  }
  log(`Downloading ${targets.length} images with ${concurrency} at a time`);

  let done = 0;
  const results = await pool(targets, concurrency, async (target) => {
    const result = await downloadOne(target, { dir, fetchImpl, force });
    done += 1;
    if (done % 25 === 0) log(`  ${done} of ${targets.length}`);
    if (result.status === 'failed') log(`  ${result.url}: ${result.error}`);
    return result;
  });

  bundle.recipes = attachLocalPaths(bundle.recipes, results, outDir);
  bundle.withheld = attachLocalPaths(bundle.withheld, results, outDir);
  const failed = results.filter((r) => r.status === 'failed');
  bundle.counts = {
    ...bundle.counts,
    imagesDownloaded: results.filter((r) => r.status === 'downloaded').length,
    imagesFailed: failed.length,
  };
  await writeFile(bundleFile, JSON.stringify(bundle, null, 2) + '\n', 'utf8');

  // Keep the per recipe files in step with the bundle.
  for (const recipe of bundle.recipes) {
    const file = path.join(outDir, 'recipes', `${safeName(recipe.mealime_id)}.json`);
    if (!existsSync(file)) continue;
    const existing = JSON.parse(await readFile(file, 'utf8'));
    if (recipe.local_images) existing.local_images = recipe.local_images;
    await writeFile(file, JSON.stringify(existing, null, 2) + '\n', 'utf8');
  }

  const summary = {
    downloaded: bundle.counts.imagesDownloaded,
    skipped: results.filter((r) => r.status === 'skipped').length,
    failed,
  };
  log('');
  log(`Downloaded ${summary.downloaded}, already had ${summary.skipped}, failed ${failed.length}.`);
  if (failed.length) log('Re-run to retry the failures. Images live in images/.');
  return summary;
}
