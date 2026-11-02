// Download each recipe's photo so the app has it offline.
//
// NYT serves these from a public image CDN with no sign in, which is how the
// recipe page itself loads them. They go next to the import file, the same way
// the rescued Mealime photos do, and the app reads them from there.
//
// Read only, and narrow: GET requests, to NYT image hosts only, both enforced
// below rather than promised in a comment.

import { mkdir, writeFile } from 'node:fs/promises';
import { extname, join } from 'node:path';

const HOSTS = new Set(['static01.nyt.com', 'static01.nytimes.com', 'cooking.nytimes.com']);
const USABLE = new Set(['.jpg', '.jpeg', '.png', '.webp']);

/** Whether this is an NYT image we are willing to fetch. */
export function isAllowed(url) {
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' && HOSTS.has(parsed.hostname);
  } catch {
    return false;
  }
}

/**
 * The best of a recipe's image urls.
 *
 * NYT names its sizes in the filename. "articleLarge" and "superJumbo" are the
 * big ones and "thumbStandard" is a 75 pixel square, which would look like a
 * mistake on a phone. Where nothing in the name says, the first one wins,
 * because JSON-LD lists the primary image first.
 */
export function pickImageURL(urls) {
  const usable = (Array.isArray(urls) ? urls : []).filter(isAllowed);
  if (usable.length === 0) return null;

  const rank = (url) => {
    const lower = url.toLowerCase();
    if (lower.includes('superjumbo')) return 0;
    if (lower.includes('articlelarge') || lower.includes('-large')) return 1;
    if (lower.includes('thumb') || lower.includes('square') || lower.includes('small')) return 3;
    return 2;
  };

  return [...usable].sort((a, b) => rank(a) - rank(b))[0];
}

function extensionFor(url) {
  const found = extname(new URL(url).pathname).toLowerCase();
  return USABLE.has(found) ? found : '.jpg';
}

/**
 * Downloads one photo per recipe and fills in `imageFile`.
 *
 * A photo that will not download is not an error. The recipe is worth having
 * without it, and failing a 169 recipe import over one picture would be a bad
 * trade. `onProgress` is called so a long run can say where it is.
 */
export async function downloadPhotos(recipes, { outDir, folderName = 'images', pauseMs = 150, onProgress } = {}) {
  const destination = join(outDir, folderName);
  await mkdir(destination, { recursive: true });

  let downloaded = 0;
  let missing = 0;
  let failed = 0;
  let bytes = 0;

  for (const [index, recipe] of recipes.entries()) {
    const url = pickImageURL(recipe.imageURLs);
    if (!url) {
      missing += 1;
    } else {
      try {
        const response = await fetch(url, { method: 'GET', redirect: 'follow' });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const buffer = Buffer.from(await response.arrayBuffer());
        if (buffer.length === 0) throw new Error('empty response');

        const name = `${recipe.externalID}${extensionFor(url)}`;
        await writeFile(join(destination, name), buffer);
        recipe.imageFile = `${folderName}/${name}`;
        downloaded += 1;
        bytes += buffer.length;
      } catch {
        failed += 1;
      }
      await new Promise((resolve) => setTimeout(resolve, pauseMs));
    }

    onProgress?.(index + 1, recipes.length, { downloaded, failed, missing });
  }

  return { downloaded, missing, failed, bytes };
}
