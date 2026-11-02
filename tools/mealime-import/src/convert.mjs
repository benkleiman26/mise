// Reshape one rescued Mealime recipe into Mise's import shape.
//
// This deliberately does not parse ingredient lines. "2 scallions, trimmed then
// sliced crosswise 1/4-inch-thick" is one string here and stays one string.
// IngredientParser in the app turns it into a quantity, a unit, a name and a
// preparation, and it has 52 tested cases for exactly this kind of line. A
// second parser written here would be a second set of answers to the same
// question, and the two would drift.
//
// Pure functions, no file system. The CLI does the reading and writing.

export const IMPORT_FORMAT = 'mise-recipe-import';
export const IMPORT_VERSION = 1;

/** Mealime writes "" rather than leaving a field out. */
const text = (value) => (typeof value === 'string' ? value.trim() : '');

const positiveInt = (value) => {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.round(n) : null;
};

/**
 * Lines that are page furniture rather than food.
 *
 * Mealime's "import from a link" captured whatever the page had where the
 * ingredients were, so the owner's library contains "Recent Posts",
 * "^ Back to Top", "Pinch of Yum logo", "5 (from 113 ratings)" and a raw
 * anchor tag. Twenty or so lines out of 2436.
 *
 * Every rule here is narrow on purpose. A junk line that gets through costs
 * one odd row in the Other aisle. A real ingredient that gets dropped means
 * standing in the kitchen without it, so the bar for dropping is high.
 */
const JUNK = [
  /^<[a-z/!]/i,                               // a raw html tag
  /^\^?\s*back to top/i,
  /^recent posts?$/i,
  /\blogo$/i,
  /^mobile search/i,
  /^\d+\s*\(from [\d,]+ ratings?\)$/i,        // a star rating widget
  /^(toppings?|remaining ingredients|baked goods|travel|pack for lunch)\s*:?\s*$/i,
  /^ingredients?\d/i,                         // "Ingredients2 1/2 cups ..."
  /^ingredients .*\b1x2x3x/i,                 // a recipe card's scaling control
  /▢/,                                        // a recipe card checkbox glyph
  /^(february|january|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i,
];

export function isJunk(line) {
  const text = String(line ?? '').trim();
  if (!text) return true;
  // Nothing to shop for without a letter in it.
  if (!/[a-z]/i.test(text)) return true;
  return JUNK.some((pattern) => pattern.test(text));
}

/**
 * One ingredient line, as written.
 *
 * Most of this library was imported by the owner rather than published by
 * Mealime, and in those records the whole line sits in `ingredient_name` with
 * `quantity` empty. Mealime's own recipes fill `quantity` separately. Both
 * shapes have to come out as one readable line.
 */
export function ingredientLine(item) {
  if (!item || typeof item !== 'object') return '';

  const raw = text(item.raw);
  const name = text(item.ingredient_name);
  const quantity = text(item.quantity);

  // `raw` is the line as Mealime stored it and is trusted first, but only when
  // it actually carries the quantity. A `raw` that equals the bare name while
  // `quantity` holds "2 tbsp" would throw the amount away.
  if (raw && (!quantity || raw.toLowerCase().includes(quantity.toLowerCase()))) {
    return raw;
  }
  if (!name) return raw || quantity;
  if (!quantity) return name;
  if (name.toLowerCase().startsWith(quantity.toLowerCase())) return name;
  return `${quantity} ${name}`;
}

/** One step. Mealime splits a step into a main sentence and an aside. */
export function stepText(instruction) {
  if (!instruction || typeof instruction !== 'object') return '';
  const primary = text(instruction.primary_message);
  const secondary = text(instruction.secondary_message);
  if (!primary) return secondary;
  if (!secondary) return primary;
  return `${primary} ${secondary}`;
}

/**
 * A rescued recipe in Mise's import shape, or null when there is nothing worth
 * importing: no title, or no ingredients and no steps.
 */
export function convertRecipe(source, { defaultServings = 4 } = {}) {
  if (!source || typeof source !== 'object') return null;

  const title = text(source.name);
  if (!title) return null;

  const ingredientLines = (Array.isArray(source.line_items) ? source.line_items : [])
    .map(ingredientLine)
    .map((line) => line.trim())
    .filter((line) => line && !isJunk(line));

  const steps = (Array.isArray(source.instructions) ? source.instructions : [])
    .slice()
    .sort((a, b) => (a?.position ?? 0) - (b?.position ?? 0))
    .map(stepText)
    .map((line) => line.trim())
    .filter(Boolean);

  if (ingredientLines.length === 0 && steps.length === 0) return null;

  // Mealime leaves both of these null on a recipe the owner typed in. A made up
  // cooking time would be a lie on a screen that says "26 min", so zero stands
  // for "not recorded" and the app says so.
  const cookMinutes = positiveInt(source.cooking_minutes) ?? 0;
  const baseServings = positiveInt(source.serving_count) ?? defaultServings;

  const tags = [];
  for (const collection of Array.isArray(source.collections) ? source.collections : []) {
    const name = typeof collection === 'string' ? collection : text(collection?.name);
    if (name && !tags.includes(name)) tags.push(name);
  }

  return {
    externalID: text(source.mealime_id) || text(source.id) || null,
    title,
    summary: text(source.description) || text(source.summary),
    sourceURL: text(source.source_url) || text(source.url) || text(source.web_url) || null,
    prepMinutes: 0,
    cookMinutes,
    baseServings,
    tags,
    cookware: (Array.isArray(source.cookwares) ? source.cookwares : [])
      .map((c) => (typeof c === 'string' ? c.trim() : text(c?.name)))
      .filter(Boolean),
    ingredientLines,
    steps,
    imageURLs: (Array.isArray(source.images) ? source.images : []).filter(
      (url) => typeof url === 'string' && url.startsWith('http')
    ),
    notes: text(source.notes),
    isFavorite: source.is_favorite === true,
    timesCooked: positiveInt(source.times_cooked) ?? 0,
  };
}

/** The whole document, plus a report of what was skipped and why. */
export function convertLibrary(sources, options = {}) {
  const recipes = [];
  const skipped = [];
  const seen = new Set();
  let junkDropped = 0;

  for (const { file, recipe } of sources) {
    const before = (Array.isArray(recipe?.line_items) ? recipe.line_items : [])
      .map(ingredientLine)
      .filter((line) => line.trim()).length;
    const converted = convertRecipe(recipe, options);
    if (converted) junkDropped += before - converted.ingredientLines.length;
    if (!converted) {
      skipped.push({ file, why: 'no title, or no ingredients and no steps' });
      continue;
    }
    const key = converted.externalID || `title:${converted.title.toLowerCase()}`;
    if (seen.has(key)) {
      skipped.push({ file, why: `duplicate of ${key}` });
      continue;
    }
    seen.add(key);
    recipes.push(converted);
  }

  recipes.sort((a, b) => a.title.localeCompare(b.title));

  return {
    document: {
      format: IMPORT_FORMAT,
      version: IMPORT_VERSION,
      source: 'mealime',
      exportedAt: new Date().toISOString(),
      recipes,
    },
    report: {
      read: sources.length,
      converted: recipes.length,
      skipped,
      withoutCookTime: recipes.filter((r) => r.cookMinutes === 0).length,
      withoutSteps: recipes.filter((r) => r.steps.length === 0).length,
      withoutIngredients: recipes.filter((r) => r.ingredientLines.length === 0).length,
    junkDropped,
      ingredientLines: recipes.reduce((n, r) => n + r.ingredientLines.length, 0),
    },
  };
}
