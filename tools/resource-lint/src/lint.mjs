// Validates the JSON resources the app loads on first launch.
//
// These files decide where every grocery item lands, and a mistake in them
// fails quietly: a duplicate alias silently files an ingredient under the wrong
// aisle, an unknown unit stops a merge from happening, and neither shows up as
// a crash. Better to fail here than to notice in a store.
//
// There is no Swift toolchain in the cloud environment, so this is also the
// only place these files get checked before they reach a phone.

export const AISLES = [
  'produce', 'meat', 'seafood', 'deliAndCheese', 'dairyAndEggs', 'bakery', 'frozen',
  'nutButtersAndJams', 'bakingAndSpices', 'riceGrainsBeans', 'cannedAndJarred',
  'pastaAndSauces', 'oilsAndCondiments', 'international', 'snacks', 'beverages',
  'household', 'other',
];

export const UNITS = [
  'count', 'tsp', 'tbsp', 'cup', 'floz', 'oz', 'lb', 'g', 'kg', 'ml', 'l',
  'pinch', 'clove', 'can', 'bunch', 'package',
];

const key = (value) => String(value).trim().toLowerCase();

/** Returns a list of problems. Empty means the file is good. */
export function lintCanonicalItems(doc) {
  const problems = [];
  const fail = (message) => problems.push(message);

  if (doc?.format !== 'canonical-items') fail(`format should be "canonical-items", got ${JSON.stringify(doc?.format)}`);
  if (!Number.isInteger(doc?.version)) fail('version should be an integer');

  const order = doc?.aisleOrder ?? [];
  const missing = AISLES.filter((a) => !order.includes(a));
  const unknown = order.filter((a) => !AISLES.includes(a));
  if (missing.length) fail(`aisleOrder is missing: ${missing.join(', ')}`);
  if (unknown.length) fail(`aisleOrder has unknown aisles: ${unknown.join(', ')}`);
  if (new Set(order).size !== order.length) fail('aisleOrder repeats an aisle');

  const items = doc?.items;
  if (!Array.isArray(items) || items.length === 0) {
    fail('items should be a non-empty array');
    return problems;
  }

  // One namespace for names and aliases together. The matcher looks a string up
  // in both, so a collision between them is just as ambiguous as two identical
  // names, and section 5.3 makes canonical matching the basis of every merge.
  const claimed = new Map();
  const claim = (text, owner, kind) => {
    const k = key(text);
    const existing = claimed.get(k);
    if (existing) {
      fail(`"${text}" is claimed twice: ${existing.kind} of "${existing.owner}" and ${kind} of "${owner}"`);
      return;
    }
    claimed.set(k, { owner, kind });
  };

  for (const [index, item] of items.entries()) {
    const where = item?.name ? `"${item.name}"` : `item ${index}`;

    if (typeof item?.name !== 'string' || !item.name.trim()) {
      fail(`${where}: name is required`);
      continue;
    }
    if (item.name !== item.name.trim()) fail(`${where}: name has leading or trailing whitespace`);
    if (item.name !== item.name.toLowerCase()) fail(`${where}: name should be lowercase`);
    claim(item.name, item.name, 'name');

    if (!AISLES.includes(item.aisle)) fail(`${where}: unknown aisle ${JSON.stringify(item.aisle)}`);
    if (item.defaultUnit !== undefined && !UNITS.includes(item.defaultUnit)) {
      fail(`${where}: unknown defaultUnit ${JSON.stringify(item.defaultUnit)}`);
    }
    if (item.isStaple !== undefined && typeof item.isStaple !== 'boolean') {
      fail(`${where}: isStaple should be true or false`);
    }

    if (item.aliases !== undefined) {
      if (!Array.isArray(item.aliases)) {
        fail(`${where}: aliases should be an array`);
        continue;
      }
      for (const alias of item.aliases) {
        if (typeof alias !== 'string' || !alias.trim()) {
          fail(`${where}: empty alias`);
          continue;
        }
        if (alias !== alias.toLowerCase()) fail(`${where}: alias "${alias}" should be lowercase`);
        claim(alias, item.name, 'alias');
      }
    }
  }

  return problems;
}

/** Checks the seed recipes, including that every ingredient resolves. */
export function lintSeedRecipes(doc, canonical) {
  const problems = [];
  const fail = (message) => problems.push(message);

  if (doc?.format !== 'seed-recipes') fail(`format should be "seed-recipes", got ${JSON.stringify(doc?.format)}`);

  const known = new Set();
  for (const item of canonical?.items ?? []) {
    known.add(key(item.name));
    for (const alias of item.aliases ?? []) known.add(key(alias));
  }

  const recipes = doc?.recipes;
  if (!Array.isArray(recipes) || recipes.length === 0) {
    fail('recipes should be a non-empty array');
    return problems;
  }

  const ids = new Set();
  for (const [index, recipe] of recipes.entries()) {
    const where = recipe?.title ? `"${recipe.title}"` : `recipe ${index}`;
    if (!recipe?.id) fail(`${where}: id is required`);
    else if (ids.has(recipe.id)) fail(`${where}: duplicate id ${recipe.id}`);
    else ids.add(recipe.id);

    if (typeof recipe?.title !== 'string' || !recipe.title.trim()) fail(`${where}: title is required`);
    if (!Number.isInteger(recipe?.baseServings) || recipe.baseServings < 1) fail(`${where}: baseServings should be a positive integer`);
    if (!Number.isInteger(recipe?.totalMinutes) || recipe.totalMinutes < 1) fail(`${where}: totalMinutes should be a positive integer`);

    const ingredients = recipe?.ingredients;
    if (!Array.isArray(ingredients) || ingredients.length === 0) {
      fail(`${where}: needs ingredients`);
    } else {
      for (const ingredient of ingredients) {
        if (typeof ingredient?.name !== 'string' || !ingredient.name.trim()) {
          fail(`${where}: an ingredient has no name`);
          continue;
        }
        // Section 5.1: every seed recipe must have canonical item links set so
        // the list generator works out of the box.
        const link = ingredient.canonicalItem ?? ingredient.name;
        if (!known.has(key(link))) fail(`${where}: "${link}" is not a canonical item or alias`);
        if (ingredient.unit !== undefined && ingredient.unit !== null && !UNITS.includes(ingredient.unit)) {
          fail(`${where}: "${ingredient.name}" has unknown unit ${JSON.stringify(ingredient.unit)}`);
        }
        if (ingredient.quantity !== undefined && ingredient.quantity !== null && !(typeof ingredient.quantity === 'number' && ingredient.quantity > 0)) {
          fail(`${where}: "${ingredient.name}" has a bad quantity`);
        }
      }
    }

    const steps = recipe?.steps;
    if (!Array.isArray(steps) || steps.length === 0) {
      fail(`${where}: needs steps`);
    } else {
      // Cook mode shows each step's own ingredients underneath it, per section
      // 5.5, so a ref that points at nothing means a blank step in the app.
      const own = new Set((ingredients ?? []).map((i) => key(i?.canonicalItem ?? i?.name ?? '')));
      for (const [position, step] of steps.entries()) {
        if (typeof step?.text !== 'string' || !step.text.trim()) fail(`${where}: step ${position + 1} has no text`);
        for (const ref of step?.ingredientRefs ?? []) {
          if (!own.has(key(ref))) fail(`${where}: step ${position + 1} refers to "${ref}", which it does not list as an ingredient`);
        }
        if (step?.timerSeconds !== undefined && !(Number.isInteger(step.timerSeconds) && step.timerSeconds > 0)) {
          fail(`${where}: step ${position + 1} has a bad timerSeconds`);
        }
      }
    }

    // Section 11 and section 2: no em dashes anywhere in copy.
    const copy = JSON.stringify(recipe);
    if (copy.includes('—')) fail(`${where}: contains an em dash`);
  }

  return problems;
}
