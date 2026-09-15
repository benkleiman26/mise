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
const NOT_RECIPE_HOSTS = [
  /^(www\.)?(google|bing|duckduckgo)\./i,
  /^(www\.)?(youtube|youtu\.be|twitter|x|facebook|instagram|reddit|pinterest)\./i,
  /^(mail|drive|docs|calendar)\.google\./i,
  /^(www\.)?(amazon|github|stackoverflow)\./i,
];

/**
 * Paths that mean an account page rather than an article.
 *
 * This is the fix for a real miss: run against a real bookmarks bar, the old
 * heuristic called 14 of 49 bookmarks recipes, every one a bank or brokerage
 * login whose path happened to read as recipe shaped. The bulk import would
 * have queued them all as recipe fetches.
 */
const ACCOUNT_PATH =
  /\b(log[-_]?in|sign[-_]?in|sign[-_]?on|logon|auth|oauth|sso|account|accounts|banking|secure|portal|dashboard|billing|checkout|cart|invoice|statement|password|profile|settings|admin|support|careers|privacy|terms|customer[-_]?service|client[-_]?home|credit[-_]?cards?|loans?|mortgage|insurance|investing|brokerage|retirement)\b/i;

/** Sites that publish recipes, so a bookmark there is one with high confidence. */
const FOOD_HOSTS =
  /(cooking\.nytimes|seriouseats|smittenkitchen|bonappetit|epicurious|food52|allrecipes|foodnetwork|simplyrecipes|budgetbytes|thekitchn|delish|tasteofhome|halfbakedharvest|loveandlemons|minimalistbaker|cookieandkate|pinchofyum|americastestkitchen|kingarthurbaking|bbcgoodfood|jamieoliver|justonecookbook|thewoksoflife|recipetineats|sallysbakingaddiction|thepioneerwoman|eatingwell|myrecipes|yummly|seriouseats|nytimes\.com\/.*\/food)/i;

const RECIPE_PATH = /\b(recipes?|cook(ing)?|kitchen|bak(e|ing)|dinner|dish|meal)\b/i;
const RECIPE_TITLE = /\b(recipe|salad|soup|chicken|pasta|roast|bake[ds]?|stew|curry|risotto|taco|braise|skillet|sheet[- ]pan)\b/i;

/**
 * Why a bookmark is, or is not, thought to be a recipe.
 *
 * A tier rather than a yes or no, because the two failure modes cost different
 * amounts. Queueing a bank login as a recipe fetch is noise the user has to
 * clear; missing a real recipe loses it. So an unknown host with an
 * article-shaped path stays a `maybe` and still gets imported, while anything
 * that reads as an account page is ruled out outright.
 */
export function recipeSignal({ url, title } = {}) {
  let host;
  let pathname;
  try {
    const parsed = new URL(url);
    host = parsed.hostname;
    pathname = parsed.pathname;
  } catch {
    return 'no';
  }

  if (NOT_RECIPE_HOSTS.some((pattern) => pattern.test(host))) return 'no';
  if (nytRecipeId(url)) return 'nyt';
  if (FOOD_HOSTS.test(host)) return 'foodHost';
  // Checked after the food hosts, so a real site's "recipes/login" page is not
  // thrown away along with a bank's.
  if (ACCOUNT_PATH.test(pathname)) return 'no';
  if (RECIPE_PATH.test(host + pathname)) return 'recipePath';
  if (title && RECIPE_TITLE.test(title)) return 'recipeTitle';
  // An unknown host with a real article path. Worth a fetch, not worth
  // counting as a recipe with any confidence.
  return pathname.split('/').filter(Boolean).length >= 2 ? 'maybe' : 'no';
}

/**
 * Whether the bulk import should try this URL at all. The import fetches
 * everything it is given, so this only rules out what is certainly not a
 * recipe. Use `recipeSignal` when the confidence matters.
 */
export function looksLikeRecipe(bookmark) {
  return recipeSignal(bookmark) !== 'no';
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
