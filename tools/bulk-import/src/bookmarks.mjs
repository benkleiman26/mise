// Parser for the Netscape bookmarks format, which is what Chrome, Safari,
// Firefox and Edge all produce from "export bookmarks".
//
// This is the input to the bulk URL import in spec section 5.6a. That import is
// an app feature, not a script, so the logic here is the reference
// implementation: written and tested in Node, where testing is cheap, then
// ported to Swift in Phase 4 against these same fixtures.
//
// The format is not valid HTML or XML. Folders are <H3> followed by a nested
// <DL>, links are <DT><A HREF>, and closing tags are frequently missing, so a
// tolerant token scan beats any real parser.

const TOKEN = /<(\/?)(DL|DT|H3|A)\b([^>]*)>([^<]*)/gi;
const ATTRIBUTE = /([A-Z_]+)\s*=\s*"([^"]*)"/gi;

const ENTITIES = {
  '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'", '&#39;': "'", '&nbsp;': ' ',
};

export function decodeEntities(text) {
  return String(text ?? '')
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)))
    .replace(/&[a-z]+;|&#39;/gi, (entity) => ENTITIES[entity.toLowerCase()] ?? entity);
}

function attributesOf(raw) {
  const out = {};
  for (const match of String(raw ?? '').matchAll(ATTRIBUTE)) out[match[1].toUpperCase()] = match[2];
  return out;
}

/**
 * Reads a bookmarks export into a flat list of links, each carrying the folder
 * path it was found under.
 *
 * @returns {{ bookmarks: Array, folders: string[] }}
 */
export function parseBookmarks(html) {
  const bookmarks = [];
  const folders = new Set();
  // The root list is unnamed, so it sits at the bottom of the stack and is
  // trimmed off every path.
  const stack = ['']; 
  let pendingFolder = null;

  for (const match of String(html ?? '').matchAll(TOKEN)) {
    const [, closing, tagRaw, attributesRaw, text] = match;
    const tag = tagRaw.toUpperCase();

    if (tag === 'H3' && !closing) {
      pendingFolder = decodeEntities(text).trim();
      continue;
    }
    if (tag === 'DL') {
      if (closing) {
        if (stack.length > 1) stack.pop();
      } else {
        stack.push(pendingFolder ?? '');
        pendingFolder = null;
        const path = stack.filter(Boolean).join('/');
        if (path) folders.add(path);
      }
      continue;
    }
    if (tag === 'A' && !closing) {
      const attributes = attributesOf(attributesRaw);
      const href = attributes.HREF;
      if (!href || !/^https?:/i.test(href)) continue;
      bookmarks.push({
        url: decodeEntities(href),
        title: decodeEntities(text).trim() || null,
        folder: stack.filter(Boolean).join('/') || null,
        addedAt: attributes.ADD_DATE ? new Date(Number(attributes.ADD_DATE) * 1000).toISOString() : null,
      });
    }
  }

  return { bookmarks, folders: [...folders] };
}

export const NYT_RECIPE = /^https?:\/\/(?:www\.)?cooking\.nytimes\.com\/recipes?\/(\d+)/i;

/** The NYT numeric id, which is the key the app dedupes on. */
export function nytRecipeId(url) {
  const match = String(url ?? '').match(NYT_RECIPE);
  return match ? match[1] : null;
}

/** Hosts that are almost certainly not a recipe, so they can be set aside. */
const NOT_RECIPES = [
  /^(www\.)?(google|bing|duckduckgo)\./i,
  /^(www\.)?(youtube|youtu\.be|twitter|x|facebook|instagram|reddit|pinterest)\./i,
  /^(mail|drive|docs|calendar)\.google\./i,
  /^(www\.)?(amazon|github|stackoverflow)\./i,
];

/**
 * A guess at whether a bookmark is a recipe, used only to order the work and
 * to set expectations. The import still tries every URL, because guessing wrong
 * and skipping a real recipe is worse than one wasted fetch.
 */
export function looksLikeRecipe({ url, title }) {
  let host;
  let pathname;
  try {
    const parsed = new URL(url);
    host = parsed.hostname;
    pathname = parsed.pathname;
  } catch {
    return false;
  }
  if (NOT_RECIPES.some((pattern) => pattern.test(host))) return false;
  if (nytRecipeId(url)) return true;
  if (/recipe|cook|kitchen|food|bake|dinner|eats/i.test(host + pathname)) return true;
  if (title && /recipe|salad|soup|chicken|pasta|roast|bake/i.test(title)) return true;
  // A plain article URL on an unknown host may still be a recipe, so this is a
  // maybe rather than a no.
  return pathname.split('/').filter(Boolean).length >= 2;
}

/** Normalizes a URL for deduplication: no fragment, no tracking parameters. */
export function canonicalUrl(url) {
  try {
    const parsed = new URL(url);
    parsed.hash = '';
    for (const key of [...parsed.searchParams.keys()]) {
      if (/^(utm_|fbclid|gclid|mc_|ref|smid|sm[a-z]{2}|referring)/i.test(key)) parsed.searchParams.delete(key);
    }
    parsed.hostname = parsed.hostname.replace(/^www\./i, '');
    if (parsed.pathname.length > 1) parsed.pathname = parsed.pathname.replace(/\/+$/, '');
    return parsed.toString();
  } catch {
    return String(url ?? '');
  }
}
