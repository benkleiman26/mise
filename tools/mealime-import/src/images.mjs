// Find the rescued photo for a recipe, and copy it next to the import file.
//
// The rescue saved them under data/mealime/images/<mealime id>/, one folder per
// recipe, with whatever sizes Mealime served. The app cannot reach into that
// folder: it reads an import file from its own Documents directory and can only
// see what sits beside it. So the chosen photo is copied there.
//
// One photo per recipe. A library screen needs one good picture, not four
// sizes of the same one, and 424 of them at full size is a lot to carry into
// a phone's database.

import { readdir, stat, mkdir, copyFile } from 'node:fs/promises';
import { extname, join } from 'node:path';

const USABLE = new Set(['.jpg', '.jpeg', '.png', '.heic', '.webp']);

/**
 * The best photo in a folder, or null.
 *
 * Mealime names them by role: `presentation_<uuid>.jpg` is the big one and
 * `thumbnail_<uuid>.jpg` is not. Where the names say nothing, the largest file
 * wins, which is the same bet by a different route.
 */
export function pickPhoto(files) {
  const usable = files.filter((file) => USABLE.has(extname(file.name).toLowerCase()));
  if (usable.length === 0) return null;

  const byRole = (name) => {
    const lower = name.toLowerCase();
    if (lower.includes('presentation')) return 0;
    if (lower.includes('original') || lower.includes('large')) return 1;
    if (lower.includes('thumbnail') || lower.includes('thumb') || lower.includes('small')) return 3;
    return 2;
  };

  return [...usable].sort((a, b) => {
    const role = byRole(a.name) - byRole(b.name);
    if (role !== 0) return role;
    return (b.size ?? 0) - (a.size ?? 0);
  })[0];
}

/** Everything in one recipe's image folder, with sizes. Empty when there is none. */
export async function photosFor(imagesDir, recipeID) {
  if (!recipeID) return [];
  const folder = join(imagesDir, recipeID);
  let names;
  try {
    names = await readdir(folder);
  } catch {
    return [];
  }

  const files = [];
  for (const name of names) {
    try {
      const info = await stat(join(folder, name));
      if (info.isFile()) files.push({ name, size: info.size, path: join(folder, name) });
    } catch {
      // A file that cannot be read is simply not a candidate.
    }
  }
  return files;
}

/**
 * Copies one photo per recipe next to the import file and fills in
 * `imageFile`. Returns what it did, for the run's report.
 */
export async function attachPhotos(recipes, { imagesDir, outDir, folderName = 'images' }) {
  const destination = join(outDir, folderName);
  let copied = 0;
  let missing = 0;
  let bytes = 0;

  await mkdir(destination, { recursive: true });

  for (const recipe of recipes) {
    const files = await photosFor(imagesDir, recipe.externalID);
    const chosen = pickPhoto(files);
    if (!chosen) {
      missing += 1;
      continue;
    }

    const name = `${recipe.externalID}${extname(chosen.name).toLowerCase()}`;
    await copyFile(chosen.path, join(destination, name));
    recipe.imageFile = `${folderName}/${name}`;
    copied += 1;
    bytes += chosen.size ?? 0;
  }

  return { copied, missing, bytes };
}
