// Stage 2 of the rescue: turn the raw responses into the stable shape described
// in the spec, section 1a, which is what the app's Mealime importer reads.
//
// This step deliberately does not parse ingredient text. Quantity strings stay
// exactly as Mealime wrote them ("2 (15 oz) cans") so that the app can run them
// through the same IngredientParser it uses for URL imports, with one review
// screen for whatever the parser is unsure about. Doing it here would mean two
// parsers to keep in agreement.
//
// Pure functions below, so they can be re-run against saved raw files at any
// time without touching the network.

import { mkdir, readdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';

/** Reads the first key that holds a usable value. */
function pick(source, keys, fallback = null) {
  for (const key of keys) {
    const value = source?.[key];
    if (value !== undefined && value !== null && value !== '') return value;
  }
  return fallback;
}

function toInt(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return Math.round(value);
  if (typeof value === 'string') {
    const match = value.match(/\d+/);
    if (match) return Number(match[0]);
  }
  return null;
}

/** Collects image URLs from the several shapes Mealime uses. */
export function collectImages(raw) {
  const out = [];
  const push = (value) => {
    if (typeof value === 'string' && value.startsWith('http') && !out.includes(value)) out.push(value);
    else if (value && typeof value === 'object') {
      for (const nested of Object.values(value)) push(nested);
    }
  };
  for (const key of ['image_url', 'image', 'images', 'photo_url', 'photos', 'hero_image', 'image_urls']) {
    push(raw?.[key]);
  }
  return out;
}

export function normalizeCookware(raw) {
  const source = pick(raw, ['cookwares', 'cookware', 'tools'], []);
  if (!Array.isArray(source)) return [];
  return source
    .map((entry) => (typeof entry === 'string' ? entry : pick(entry, ['name', 'title', 'label'])))
    .filter((name) => typeof name === 'string' && name.trim() !== '')
    .map((name) => name.trim());
}

export function normalizeLineItems(raw) {
  const source = pick(raw, ['line_items', 'lineItems', 'ingredients', 'recipe_ingredients'], []);
  if (!Array.isArray(source)) return [];
  return source
    .map((entry) => {
      if (typeof entry === 'string') return { quantity: '', ingredient_name: entry.trim(), raw: entry };
      const name = pick(entry, ['ingredient_name', 'name', 'ingredient', 'title'], '');
      const quantity = pick(entry, ['quantity', 'amount', 'measurement', 'quantity_string'], '');
      return {
        quantity: String(quantity).trim(),
        ingredient_name: String(name).trim(),
        // Kept so the app can fall back to the original line when the split
        // between quantity and name looks wrong.
        raw: [String(quantity).trim(), String(name).trim()].filter(Boolean).join(' '),
      };
    })
    .filter((item) => item.ingredient_name !== '' || item.quantity !== '');
}

export function normalizeInstructions(raw) {
  const source = pick(raw, ['instructions', 'steps', 'directions'], []);
  if (!Array.isArray(source)) return [];
  return source
    .map((entry, index) => {
      if (typeof entry === 'string') {
        return { position: index + 1, primary_message: entry.trim(), secondary_message: '' };
      }
      const primary = pick(entry, ['primary_message', 'text', 'instruction', 'body', 'description'], '');
      const secondary = pick(entry, ['secondary_message', 'ingredients_text', 'ingredients'], '');
      return {
        position: toInt(pick(entry, ['position', 'step', 'order'])) ?? index + 1,
        primary_message: String(primary).trim(),
        // Newline separated ingredient lines for this step. This is what makes
        // the "ingredients under each step" cook view possible.
        secondary_message: Array.isArray(secondary)
          ? secondary.join('\n')
          : String(secondary ?? '').trim(),
      };
    })
    .filter((step) => step.primary_message !== '')
    .sort((a, b) => a.position - b.position);
}

export function normalizeNutrition(raw) {
  const source = pick(raw, ['nutrition', 'nutrition_facts', 'nutritional_information']);
  if (!source || typeof source !== 'object') return null;
  return source;
}

/**
 * Maps one raw recipe onto the section 1a shape.
 * Returns the recipe plus any warnings worth showing the owner before the
 * account is deleted, while re-fetching is still possible.
 */
export function normalizeRecipe(raw, { id } = {}) {
  const warnings = [];
  const recipe = {
    mealime_id: id ?? pick(raw, ['uuid', 'id', 'recipe_id'], null),
    name: pick(raw, ['name', 'title', 'recipe_name'], ''),
    serving_count: toInt(pick(raw, ['serving_count', 'servings', 'serves', 'yield', 'portions'])),
    cooking_minutes: toInt(
      pick(raw, ['cooking_minutes', 'cook_minutes', 'total_minutes', 'cooking_time', 'time_minutes'])
    ),
    units: pick(raw, ['units', 'unit_system', 'measurement_system'], 'us'),
    images: collectImages(raw),
    cookwares: normalizeCookware(raw),
    line_items: normalizeLineItems(raw),
    instructions: normalizeInstructions(raw),
    nutrition: normalizeNutrition(raw),
    source_url: pick(raw, ['source_url', 'url', 'original_url', 'link'], null),
  };

  if (!recipe.name) warnings.push('missing name');
  if (recipe.line_items.length === 0) warnings.push('no ingredients');
  if (recipe.instructions.length === 0) warnings.push('no instructions');
  if (recipe.serving_count === null) warnings.push('missing serving count');

  return { recipe, warnings };
}

/**
 * Pulls the owner's standing non-food items out of the rescued grocery lists.
 * These are the rows he adds by hand (soda, dish soap, snacks) and they must
 * survive into the new app, where they live on as manual grocery items.
 */
export function extractManualItems(groceryListPages) {
  const seen = new Map();
  const visit = (node) => {
    if (Array.isArray(node)) return node.forEach(visit);
    if (!node || typeof node !== 'object') return;

    const isManual =
      node.manual === true ||
      node.is_manual === true ||
      node.custom === true ||
      node.user_added === true ||
      node.recipe_id === null ||
      (Array.isArray(node.recipe_ids) && node.recipe_ids.length === 0);
    const name = pick(node, ['name', 'display_name', 'ingredient_name', 'title', 'item_name']);

    if (isManual && typeof name === 'string' && name.trim() !== '') {
      const key = name.trim().toLowerCase();
      if (!seen.has(key)) {
        seen.set(key, {
          name: name.trim(),
          quantity: String(pick(node, ['quantity', 'amount'], '') ?? '').trim(),
          aisle: pick(node, ['aisle', 'category', 'section', 'department'], null),
        });
      }
    }
    Object.values(node).forEach(visit);
  };
  visit(groceryListPages);
  return [...seen.values()].sort((a, b) => a.name.localeCompare(b.name));
}

/** Reads the recipe ids that the favorites collection referred to. */
export function extractFavoriteIds(favoritePages, recipeIdOf) {
  const ids = new Set();
  const visit = (node) => {
    if (Array.isArray(node)) return node.forEach(visit);
    if (!node || typeof node !== 'object') return;
    const id = recipeIdOf(node);
    if (id) ids.add(id);
    Object.values(node).forEach(visit);
  };
  visit(favoritePages);
  return [...ids];
}


// Provenance decides what the export is allowed to carry.
//
// Spec section 5.7: a user's own imports are their content and travel in full.
// Recipes Mealime wrote are Albertsons' content, so the export keeps only a
// reference (id, name, image) unless the owner explicitly asks for full content
// for his own private copy. When the signals are unclear we assume Mealime
// wrote it, because that is the choice that withholds rather than copies.

export const USER_IMPORTED = 'userImported';
export const MEALIME_AUTHORED = 'mealimeAuthored';

export function classifyProvenance({ roles = [], recipe = {}, summary = {} } = {}) {
  const reasons = [];
  const source = { ...summary, ...recipe };

  if (roles.includes('userRecipes')) reasons.push('listed under the user\'s own recipes');
  if (source.source_url) reasons.push('has a source url, so it came from elsewhere');
  for (const key of ['user_id', 'created_by_user', 'is_user_recipe', 'owned', 'user_created']) {
    if (source[key]) reasons.push(`carries ${key}`);
  }

  if (reasons.length > 0) {
    return { provenance: USER_IMPORTED, confidence: reasons.length > 1 ? 'high' : 'medium', reasons };
  }
  return {
    provenance: MEALIME_AUTHORED,
    confidence: roles.includes('favorites') ? 'medium' : 'low',
    reasons: ['no sign the user brought this recipe in, so treat it as Mealime content'],
  };
}

/** Reduces a recipe to the reference the public export may carry. */
export function toReference(recipe) {
  return {
    mealime_id: recipe.mealime_id,
    name: recipe.name,
    image: recipe.images?.[0] ?? null,
    provenance: MEALIME_AUTHORED,
    content_withheld: true,
    // Mise offers to find a comparable recipe by name rather than reproducing
    // the original. See spec section 5.7.
    note: 'Mealime wrote this recipe, so only the reference travels.',
  };
}

const MENU_TYPES = ['classic', 'lowCarb', 'keto', 'flexitarian', 'paleo', 'vegetarian', 'pescetarian', 'vegan'];
const RESTRICTIONS = ['shellfish', 'gluten', 'dairy', 'peanut', 'treeNut', 'soy', 'egg', 'sesame', 'mustard', 'sulfite', 'nightshade'];

function camel(value) {
  return String(value)
    .trim()
    .replace(/[\s_-]+(.)/g, (_, c) => c.toUpperCase())
    .replace(/^(.)/, (_, c) => c.toLowerCase());
}

/** Maps Mealime preferences onto Mise's HouseholdPreferences shape. */
export function normalizePreferences(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const body = raw.preferences ?? raw.data ?? raw;

  const menuRaw = camel(pick(body, ['menu_type', 'menuType', 'diet', 'diet_type'], '') ?? '');
  const menuType = MENU_TYPES.find((m) => m.toLowerCase() === menuRaw.toLowerCase()) ?? null;

  const restrictionSource = pick(body, ['restrictions', 'allergies', 'allergies_and_restrictions', 'exclusions'], []) ?? [];
  const restrictions = (Array.isArray(restrictionSource) ? restrictionSource : [])
    .map((entry) => camel(typeof entry === 'string' ? entry : pick(entry, ['name', 'key'], '')))
    .map((entry) => RESTRICTIONS.find((r) => r.toLowerCase() === entry.toLowerCase()))
    .filter(Boolean);

  const dislikedSource = pick(body, ['disliked_ingredients', 'dislikes', 'dislikedIngredients'], []) ?? [];
  const dislikedIngredients = (Array.isArray(dislikedSource) ? dislikedSource : [])
    .map((entry) => (typeof entry === 'string' ? entry : pick(entry, ['name', 'ingredient_name'], '')))
    .map((entry) => String(entry).trim())
    .filter(Boolean);

  const servings = toInt(pick(body, ['meal_size', 'serving_count', 'default_servings', 'servings']));
  const units = String(pick(body, ['units', 'unit_system', 'measurement_system'], 'us')).toLowerCase().startsWith('m')
    ? 'metric'
    : 'us';

  return { menuType, restrictions, dislikedIngredients, defaultServings: servings, units };
}

/**
 * Builds mealime-export.json, the interchange file that Mise's
 * "Import from Mealime" screen reads. Keep the shape stable and bump `version`
 * rather than changing a field's meaning, because people will have saved files
 * on disk from before the shutdown.
 */
export function buildBundle({
  recipes = [],
  index = [],
  favoriteIds = [],
  manualItems = [],
  preferences = null,
  includeMealimeContent = false,
  method = 'api',
  toolVersion = '1.0.0',
  now = () => new Date().toISOString(),
} = {}) {
  const rolesById = new Map(index.map((entry) => [String(entry.id), entry]));
  const favoriteSet = new Set(favoriteIds.map(String));

  const out = [];
  const references = [];
  for (const recipe of recipes) {
    const entry = rolesById.get(String(recipe.mealime_id)) ?? {};
    const { provenance, confidence, reasons } = classifyProvenance({
      roles: entry.roles ?? [],
      recipe,
      summary: entry.summary ?? {},
    });

    if (provenance === MEALIME_AUTHORED && !includeMealimeContent) {
      references.push(toReference(recipe));
      continue;
    }
    out.push({ ...recipe, provenance, provenance_confidence: confidence, provenance_reasons: reasons });
  }

  // A withheld recipe appears both in `recipes` and in `references`, so collapse
  // by id before building the favorites list or every withheld favorite is
  // listed twice.
  const byId = new Map();
  for (const entry of [...recipes, ...references]) {
    const key = String(entry.mealime_id);
    if (!byId.has(key)) byId.set(key, entry);
  }
  const favorites = [...byId.values()]
    .filter((r) => favoriteSet.has(String(r.mealime_id)))
    .map((r) => ({ mealime_id: r.mealime_id, name: r.name, image: r.images?.[0] ?? r.image ?? null }));

  return {
    format: 'mealime-export',
    version: 1,
    exportedAt: now(),
    source: { tool: 'mealime-export', toolVersion, method, includesMealimeContent: includeMealimeContent },
    counts: {
      recipes: out.length,
      withheldReferences: references.length,
      favorites: favorites.length,
      manualItems: manualItems.length,
    },
    preferences,
    favorites,
    recipes: out,
    withheld: references,
    manualItems,
  };
}

async function readJsonFiles(dir) {
  if (!existsSync(dir)) return [];
  const files = (await readdir(dir)).filter((f) => f.endsWith('.json'));
  const out = [];
  for (const file of files) {
    out.push({ file, body: JSON.parse(await readFile(path.join(dir, file), 'utf8')) });
  }
  return out;
}

async function writeJson(file, value) {
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(value, null, 2) + '\n', 'utf8');
}

/** Runs stage 2 over an already rescued outDir. Never touches the network. */
export async function runNormalize({ outDir, includeMealimeContent = false, log = console.log }) {
  const rawDir = path.join(outDir, 'raw');
  if (!existsSync(rawDir)) throw new Error(`No raw export at ${rawDir}. Run the export step first.`);

  const { recipeId } = await import('./export.mjs');
  const rawRecipes = await readJsonFiles(path.join(rawDir, 'recipes'));
  const collections = await readJsonFiles(path.join(rawDir, 'collections'));
  const index = await readJsonIfPresent(path.join(rawDir, '_recipe_index.json'), []);
  const rawPreferences = await readJsonIfPresent(path.join(rawDir, 'preferences.json'), null);
  const method = existsSync(path.join(rawDir, 'localstorage-dump.json')) ? 'localstorage' : 'api';

  const report = { normalizedAt: new Date().toISOString(), recipes: [], warningsByRecipe: {} };
  const normalized = [];
  for (const { file, body } of rawRecipes) {
    const id = decodeURIComponent(file.replace(/\.json$/, ''));
    // Detail responses are sometimes wrapped in an envelope.
    const source = body?.recipe ?? body?.data ?? body;
    const { recipe, warnings } = normalizeRecipe(source, { id });
    await writeJson(path.join(outDir, 'recipes', file), recipe);
    normalized.push(recipe);
    report.recipes.push({ id, name: recipe.name, warnings });
    if (warnings.length) {
      report.warningsByRecipe[id] = warnings;
      log(`  ${id}: ${warnings.join(', ')}`);
    }
  }

  // The API path learns favorites from a favorites collection response. The
  // browser path has no API to ask, so it records which page each recipe was
  // seen on instead, and the roles in the index carry the same information.
  const favoritePages = collections.filter((c) => c.file.startsWith('favorites.')).map((c) => c.body);
  const favoriteIds = extractFavoriteIds(favoritePages, recipeId);
  const fromIndex = favoritesFromIndex(index);
  for (const id of fromIndex) {
    if (!favoriteIds.includes(id)) favoriteIds.push(id);
  }
  await writeJson(path.join(outDir, 'favorites.json'), favoriteIds);

  const groceryPages = collections.filter((c) => c.file.startsWith('groceryLists.')).map((c) => c.body);
  const manualItems = extractManualItems(groceryPages);
  await writeJson(path.join(outDir, 'manual_items.json'), manualItems);

  const preferences = normalizePreferences(rawPreferences);
  const bundle = buildBundle({
    recipes: normalized,
    index,
    favoriteIds,
    manualItems,
    preferences,
    includeMealimeContent,
    method,
  });
  await writeJson(path.join(outDir, 'mealime-export.json'), bundle);
  await writeJson(path.join(outDir, '_normalize_report.json'), report);

  const withWarnings = report.recipes.filter((r) => r.warnings.length).length;
  log('');
  log(`Normalized ${report.recipes.length} recipes, ${withWarnings} with warnings.`);
  log(`Favorites: ${favoriteIds.length}. Manual grocery items: ${manualItems.length}.`);
  log(`Wrote mealime-export.json with ${bundle.counts.recipes} recipes in full.`);
  if (bundle.counts.withheldReferences > 0) {
    log(
      `${bundle.counts.withheldReferences} recipes look like Mealime's own content, so only the ` +
        'reference travels. Pass --include-mealime-content for a private copy that keeps the text.'
    );
  }
  if (withWarnings > 0) log('See _normalize_report.json. Fix and re-run, no re-fetch needed.');
  return { report, bundle };
}

/** Reads favorite ids out of the recipe index, used by the browser path. */
export function favoritesFromIndex(index = []) {
  return index.filter((entry) => (entry.roles ?? []).includes('favorites')).map((entry) => String(entry.id));
}

async function readJsonIfPresent(file, fallback) {
  if (!existsSync(file)) return fallback;
  return JSON.parse(await readFile(file, 'utf8'));
}
