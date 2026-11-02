// schema.org Recipe JSON-LD, as NYT Cooking publishes it, reshaped into Mise's
// import format.
//
// Same split as the Mealime importer: this does not parse ingredient lines.
// "2 garlic cloves, finely chopped" comes out of here as that string, and
// IngredientParser in the app turns it into a quantity, a unit, a name and a
// preparation. One parser, one set of answers.

export const IMPORT_FORMAT = 'mise-recipe-import';
export const IMPORT_VERSION = 1;

const text = (value) => (typeof value === 'string' ? value.trim() : '');

/** "PT1H30M" is ninety minutes. Returns 0 when there is nothing to read. */
export function minutesFromDuration(value) {
  const raw = text(value);
  const match = /^P(?:([\d.]+)D)?(?:T(?:([\d.]+)H)?(?:([\d.]+)M)?(?:([\d.]+)S)?)?$/i.exec(raw);
  if (!match) return 0;
  const [, days, hours, minutes, seconds] = match.map((v) => (v ? Number(v) : 0));
  const total = days * 1440 + hours * 60 + minutes + seconds / 60;
  return Number.isFinite(total) && total > 0 ? Math.round(total) : 0;
}

/** "4 servings", "4 to 6 servings", 4. Returns null when it cannot tell. */
export function servingsFrom(value) {
  const candidates = Array.isArray(value) ? value : [value];
  for (const candidate of candidates) {
    if (typeof candidate === 'number' && candidate > 0) return Math.round(candidate);
    const found = /(\d+)/.exec(text(candidate));
    if (found) {
      const n = Number(found[1]);
      if (n > 0 && n < 100) return n;
    }
  }
  return null;
}

/**
 * Instructions arrive as strings, as HowToStep objects, or as HowToSections
 * with the steps nested inside them. All three appear on NYT Cooking.
 */
export function stepsFrom(value) {
  const out = [];
  const walk = (node) => {
    if (node == null) return;
    if (Array.isArray(node)) {
      node.forEach(walk);
      return;
    }
    if (typeof node === 'string') {
      const line = stripTags(node);
      if (line) out.push(line);
      return;
    }
    if (typeof node !== 'object') return;

    if (Array.isArray(node.itemListElement)) {
      walk(node.itemListElement);
      return;
    }
    const line = stripTags(node.text ?? node.name ?? '');
    if (line) out.push(line);
  };
  walk(value);
  return out;
}

export function stripTags(value) {
  return text(value)
    .replace(/<[^>]*>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function imageURLs(value) {
  const out = [];
  const walk = (node) => {
    if (!node) return;
    if (Array.isArray(node)) return node.forEach(walk);
    if (typeof node === 'string') {
      if (node.startsWith('http')) out.push(node);
      return;
    }
    if (typeof node === 'object') walk(node.url ?? node.contentUrl);
  };
  walk(value);
  return out;
}

/**
 * One fetched recipe in Mise's import shape, or null when there is nothing
 * worth importing.
 *
 * `entry` is what the browser script collected: the JSON-LD plus the url, the
 * folders it was filed under, and whether it is in the Cooked list.
 */
export function convertRecipe(entry) {
  const ld = entry?.jsonld;
  if (!ld || typeof ld !== 'object') return null;

  const title = stripTags(ld.name);
  if (!title) return null;

  const ingredientLines = (Array.isArray(ld.recipeIngredient) ? ld.recipeIngredient : [])
    .map(stripTags)
    .filter(Boolean);
  const steps = stepsFrom(ld.recipeInstructions);
  if (ingredientLines.length === 0 && steps.length === 0) return null;

  const url = text(entry.url) || text(ld.url) || null;
  // The recipe id out of the url, so reimporting updates rather than
  // duplicating even if the title is edited later.
  const external = /\/recipes\/(\d+)/.exec(url ?? '')?.[1] ?? url ?? title.toLowerCase();

  const tags = [];
  for (const folder of Array.isArray(entry.folders) ? entry.folders : []) {
    const name = text(folder);
    if (name && !tags.includes(name)) tags.push(name);
  }
  for (const keyword of String(ld.recipeCategory ?? '').split(',')) {
    const name = text(keyword);
    if (name && !tags.includes(name)) tags.push(name);
  }

  const cook = minutesFromDuration(ld.cookTime);
  const prep = minutesFromDuration(ld.prepTime);
  const total = minutesFromDuration(ld.totalTime);

  return {
    externalID: String(external),
    /// Filled in by the download step: the photo's name in the images folder
    /// beside the import file.
    imageFile: null,
    title,
    summary: stripTags(ld.description),
    sourceURL: url,
    prepMinutes: prep,
    // When only a total is published, it goes in cookMinutes so prep plus cook
    // still adds up to what NYT said rather than to double it.
    cookMinutes: cook || Math.max(0, total - prep),
    baseServings: servingsFrom(ld.recipeYield) ?? 4,
    tags,
    cookware: [],
    ingredientLines,
    steps,
    imageURLs: imageURLs(ld.image),
    notes: '',
    isFavorite: false,
    timesCooked: entry.cooked === true ? 1 : 0,
  };
}

export function convertLibrary(entries) {
  const recipes = [];
  const skipped = [];
  const seen = new Set();

  for (const entry of entries) {
    const converted = convertRecipe(entry);
    const where = entry?.url ?? entry?.jsonld?.name ?? 'unknown';
    if (!converted) {
      skipped.push({ where, why: 'no title, or no ingredients and no steps' });
      continue;
    }
    if (seen.has(converted.externalID)) {
      skipped.push({ where, why: `duplicate of ${converted.externalID}` });
      continue;
    }
    seen.add(converted.externalID);
    recipes.push(converted);
  }

  recipes.sort((a, b) => a.title.localeCompare(b.title));

  return {
    document: {
      format: IMPORT_FORMAT,
      version: IMPORT_VERSION,
      source: 'nyt',
      exportedAt: new Date().toISOString(),
      recipes,
    },
    report: {
      read: entries.length,
      converted: recipes.length,
      skipped,
      cooked: recipes.filter((r) => r.timesCooked > 0).length,
      withoutTime: recipes.filter((r) => r.prepMinutes + r.cookMinutes === 0).length,
      withoutSteps: recipes.filter((r) => r.steps.length === 0).length,
      ingredientLines: recipes.reduce((n, r) => n + r.ingredientLines.length, 0),
    },
  };
}
