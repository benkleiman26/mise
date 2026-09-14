import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';

import {
  normalizeUserRecipe,
  splitBodyIntoSteps,
  normalizeCollections,
  normalizeHistory,
  collectImages,
  extractFavoriteIds,
  extractManualItems,
  normalizeCookware,
  normalizeInstructions,
  normalizeLineItems,
  normalizeRecipe,
  classifyProvenance,
  buildBundle,
  normalizePreferences,
  USER_IMPORTED,
  MEALIME_AUTHORED,
} from '../src/normalize.mjs';
import { recipeId } from '../src/export.mjs';

// Shaped after the Mealime recipe JSON described in the spec, section 1a.
const MEALIME_RECIPE = {
  uuid: 'a1b2c3',
  name: 'Sesame Soba Noodles',
  serving_count: 4,
  cooking_minutes: 25,
  units: 'us',
  image_url: 'https://example.test/soba.jpg',
  cookwares: [{ name: "chef's knife" }, { name: 'colander' }, { name: 'small saucepan' }],
  line_items: [
    { quantity: '3 tbsp', ingredient_name: 'sesame oil' },
    { quantity: '2 (15 oz) cans', ingredient_name: 'chickpeas' },
    { quantity: '1 bunch', ingredient_name: 'scallions' },
  ],
  instructions: [
    { position: 1, primary_message: 'Boil the soba.', secondary_message: '8 oz soba noodles' },
    { position: 2, primary_message: 'Whisk the sauce.', secondary_message: '3 tbsp sesame oil\n2 tbsp soy sauce' },
  ],
  nutrition: { energy: 520, carbs: 62, fat: 18, protein: 19, fiber: 9 },
};

describe('normalizeRecipe', () => {
  test('maps the documented Mealime shape without losing anything', () => {
    const { recipe, warnings } = normalizeRecipe(MEALIME_RECIPE, { id: 'a1b2c3' });
    assert.equal(recipe.mealime_id, 'a1b2c3');
    assert.equal(recipe.name, 'Sesame Soba Noodles');
    assert.equal(recipe.serving_count, 4);
    assert.equal(recipe.cooking_minutes, 25);
    assert.deepEqual(recipe.cookwares, ["chef's knife", 'colander', 'small saucepan']);
    assert.equal(recipe.line_items.length, 3);
    assert.equal(recipe.instructions.length, 2);
    assert.equal(recipe.nutrition.energy, 520);
    assert.deepEqual(warnings, []);
  });

  test('keeps quantity strings verbatim so the app parser sees what Mealime wrote', () => {
    const { recipe } = normalizeRecipe(MEALIME_RECIPE);
    const chickpeas = recipe.line_items.find((i) => i.ingredient_name === 'chickpeas');
    assert.equal(chickpeas.quantity, '2 (15 oz) cans');
    assert.equal(chickpeas.raw, '2 (15 oz) cans chickpeas');
  });

  test('warns rather than throws when the shape is unexpected', () => {
    const { recipe, warnings } = normalizeRecipe({ id: 'x' });
    assert.equal(recipe.name, '');
    assert.deepEqual(recipe.line_items, []);
    assert.deepEqual(warnings.sort(), ['missing name', 'missing serving count', 'no ingredients', 'no instructions'].sort());
  });

  test('reads serving counts out of free text yields', () => {
    const { recipe } = normalizeRecipe({ name: 'x', yield: '4 servings' });
    assert.equal(recipe.serving_count, 4);
  });
});

describe('normalizeLineItems', () => {
  test('accepts plain strings as well as objects', () => {
    const items = normalizeLineItems({ ingredients: ['1 large lemon', '2 cloves garlic'] });
    assert.equal(items.length, 2);
    assert.equal(items[0].ingredient_name, '1 large lemon');
  });

  test('drops entries with neither a name nor a quantity', () => {
    const items = normalizeLineItems({ line_items: [{ quantity: '', ingredient_name: '' }, { ingredient_name: 'salt' }] });
    assert.equal(items.length, 1);
    assert.equal(items[0].ingredient_name, 'salt');
  });
});

describe('normalizeInstructions', () => {
  test('keeps per step ingredient lines, which the cook view needs', () => {
    const steps = normalizeInstructions(MEALIME_RECIPE);
    assert.equal(steps[1].secondary_message, '3 tbsp sesame oil\n2 tbsp soy sauce');
  });

  test('sorts by position and numbers bare strings', () => {
    const steps = normalizeInstructions({
      instructions: [
        { position: 2, primary_message: 'second' },
        { position: 1, primary_message: 'first' },
      ],
    });
    assert.deepEqual(steps.map((s) => s.primary_message), ['first', 'second']);
    assert.deepEqual(normalizeInstructions({ steps: ['a', 'b'] }).map((s) => s.position), [1, 2]);
  });

  test('joins array valued secondary messages', () => {
    const steps = normalizeInstructions({ instructions: [{ text: 'Cook', ingredients: ['1 tsp salt', '2 tbsp oil'] }] });
    assert.equal(steps[0].secondary_message, '1 tsp salt\n2 tbsp oil');
  });
});

describe('normalizeCookware', () => {
  test('handles both object and string forms', () => {
    assert.deepEqual(normalizeCookware({ cookwares: [{ name: 'whisk' }] }), ['whisk']);
    assert.deepEqual(normalizeCookware({ cookware: ['whisk', '  '] }), ['whisk']);
    assert.deepEqual(normalizeCookware({}), []);
  });
});

describe('collectImages', () => {
  test('gathers urls from nested shapes and deduplicates', () => {
    const images = collectImages({
      image_url: 'https://a.test/1.jpg',
      images: { large: 'https://a.test/2.jpg', small: 'https://a.test/1.jpg' },
    });
    assert.deepEqual(images, ['https://a.test/1.jpg', 'https://a.test/2.jpg']);
  });
});

describe('extractManualItems', () => {
  test('finds hand added non food rows anywhere in the grocery payload', () => {
    const pages = [
      {
        grocery_list: {
          items: [
            { name: 'sesame oil', recipe_ids: ['r1'], quantity: '3 tbsp' },
            { name: 'Dish soap', is_manual: true, quantity: '1' },
            { name: 'Seltzer', manual: true, aisle: 'Beverages' },
          ],
        },
      },
    ];
    const items = extractManualItems(pages);
    assert.deepEqual(items.map((i) => i.name), ['Dish soap', 'Seltzer']);
    assert.equal(items[1].aisle, 'Beverages');
  });

  test('deduplicates case insensitively', () => {
    const items = extractManualItems([
      { items: [{ name: 'Soda', manual: true }, { name: 'soda', manual: true }] },
    ]);
    assert.equal(items.length, 1);
  });
});

describe('extractFavoriteIds', () => {
  test('pulls ids out of whatever envelope the API used', () => {
    const ids = extractFavoriteIds([{ data: [{ uuid: 'a' }, { uuid: 'b' }] }], recipeId);
    assert.deepEqual(ids.sort(), ['a', 'b']);
  });
});

describe('classifyProvenance', () => {
  test('treats a recipe from the user\'s own list as theirs', () => {
    const result = classifyProvenance({ roles: ['userRecipes'], recipe: {} });
    assert.equal(result.provenance, USER_IMPORTED);
  });

  test('treats a source url as proof the user brought it in', () => {
    const result = classifyProvenance({ roles: [], recipe: { source_url: 'https://blog.test/x' } });
    assert.equal(result.provenance, USER_IMPORTED);
  });

  test('assumes Mealime wrote it when there is no signal', () => {
    const result = classifyProvenance({ roles: ['favorites'], recipe: {} });
    assert.equal(result.provenance, MEALIME_AUTHORED);
  });

  test('reports higher confidence when several signals agree', () => {
    const result = classifyProvenance({ roles: ['userRecipes'], recipe: { source_url: 'https://a.test' } });
    assert.equal(result.confidence, 'high');
  });
});

describe('buildBundle', () => {
  const ownRecipe = { mealime_id: 'own', name: 'My Chili', images: ['https://a.test/1.jpg'], line_items: [] };
  const theirRecipe = { mealime_id: 'theirs', name: 'Mealime Tacos', images: ['https://a.test/2.jpg'], line_items: [] };
  const index = [
    { id: 'own', roles: ['userRecipes'], summary: {} },
    { id: 'theirs', roles: ['favorites'], summary: {} },
  ];

  test('withholds the text of Mealime authored recipes by default', () => {
    const bundle = buildBundle({ recipes: [ownRecipe, theirRecipe], index, favoriteIds: ['theirs'] });
    assert.deepEqual(bundle.recipes.map((r) => r.mealime_id), ['own']);
    assert.equal(bundle.withheld.length, 1);
    assert.equal(bundle.withheld[0].content_withheld, true);
    assert.equal(bundle.withheld[0].name, 'Mealime Tacos');
    assert.equal(bundle.counts.withheldReferences, 1);
  });

  test('keeps everything when the owner asks for a private copy', () => {
    const bundle = buildBundle({ recipes: [ownRecipe, theirRecipe], index, includeMealimeContent: true });
    assert.equal(bundle.recipes.length, 2);
    assert.equal(bundle.withheld.length, 0);
    assert.equal(bundle.source.includesMealimeContent, true);
  });

  test('keeps favorites as references even when their content is withheld', () => {
    const bundle = buildBundle({ recipes: [ownRecipe, theirRecipe], index, favoriteIds: ['theirs'] });
    assert.deepEqual(bundle.favorites, [
      { mealime_id: 'theirs', name: 'Mealime Tacos', image: 'https://a.test/2.jpg' },
    ]);
  });

  test('declares a stable format and version', () => {
    const bundle = buildBundle({});
    assert.equal(bundle.format, 'mealime-export');
    assert.equal(bundle.version, 2);
    assert.deepEqual(bundle.collections, []);
    assert.deepEqual(bundle.cookHistory, []);
  });
});

describe('normalizePreferences', () => {
  test('maps Mealime preferences onto the Mise shape', () => {
    const prefs = normalizePreferences({
      menu_type: 'Pescetarian',
      allergies: ['tree nut', 'shellfish'],
      disliked_ingredients: ['olives'],
      meal_size: 4,
      units: 'us',
    });
    assert.equal(prefs.menuType, 'pescetarian');
    assert.deepEqual(prefs.restrictions, ['treeNut', 'shellfish']);
    assert.deepEqual(prefs.dislikedIngredients, ['olives']);
    assert.equal(prefs.defaultServings, 4);
    assert.equal(prefs.units, 'us');
  });

  test('drops values that are not in our enums rather than inventing them', () => {
    const prefs = normalizePreferences({ menu_type: 'Carnivore', allergies: ['pollen'] });
    assert.equal(prefs.menuType, null);
    assert.deepEqual(prefs.restrictions, []);
  });

  test('detects metric', () => {
    assert.equal(normalizePreferences({ units: 'metric' }).units, 'metric');
  });

  test('returns null when there are no preferences to map', () => {
    assert.equal(normalizePreferences(null), null);
  });
});

describe('user recipes from the account object', () => {
  const raw = {
    uid: 'u-1',
    name: 'Spicy Rice Noodles',
    body: 'Heat the oven.\n\nCut the tofu into cubes\nand toss.\n\nBake.',
    ingredients: ['12 ounces firm tofu', '2 teaspoons sesame oil'],
    is_deleted: false,
    import_url: 'https://cooking.nytimes.com/recipes/1019461-spicy',
    thumbnail_image_url: 'https://cdn-uploads.mealime.com/t.jpg',
    presentation_image_url: 'https://cdn-uploads.mealime.com/p.jpg',
    base_servings: 4,
  };

  test('splits the prose body on blank lines and keeps single newlines', () => {
    const steps = splitBodyIntoSteps(raw.body);
    assert.equal(steps.length, 3);
    assert.equal(steps[1].primary_message, 'Cut the tofu into cubes\nand toss.');
    assert.equal(steps[2].position, 3);
  });

  test('maps onto the shared recipe shape with the import url as source', () => {
    const { recipe, warnings } = normalizeUserRecipe(raw, { id: 'u-1' });
    assert.equal(recipe.mealime_id, 'u-1');
    assert.equal(recipe.source_url, raw.import_url);
    assert.equal(recipe.serving_count, 4);
    assert.equal(recipe.line_items.length, 2);
    assert.equal(recipe.line_items[0].raw, '12 ounces firm tofu');
    assert.deepEqual(recipe.images, [raw.presentation_image_url, raw.thumbnail_image_url]);
    assert.equal(recipe.user_recipe, true);
    assert.deepEqual(warnings, []);
  });

  test('flags deleted recipes instead of dropping them', () => {
    const { recipe, warnings } = normalizeUserRecipe({ ...raw, is_deleted: true });
    assert.equal(recipe.is_deleted, true);
    assert.ok(warnings.some((w) => /deleted/.test(w)));
  });

  test('user recipes classify as the user\'s own content', () => {
    const { recipe } = normalizeUserRecipe(raw, { id: 'u-1' });
    const { provenance, confidence } = classifyProvenance({ roles: ['userRecipes'], recipe });
    assert.equal(provenance, 'userImported');
    assert.equal(confidence, 'high');
  });
});

describe('collections and history from the account object', () => {
  const account = {
    favourites: [{ id: 1, recipe_variant_id: 4307, published_recipe_uuid: 'pub-1' }],
    collections: [
      { id: 1, name: 'Noodles', is_deleted: false, created_at: 5, members: [{ type: 'user_recipe', user_recipe_uid: 'u-1' }] },
      { id: 2, name: 'Old', is_deleted: true, members: [] },
    ],
    history: [
      { id: 10, created_at: 100, meals: [{ id: 1, is_cooked: true, variant_id: 4307 }], user_meals: [{ id: 2, is_cooked: false, user_recipe_uid: 'u-1' }] },
      { id: 11, created_at: 200, meals: [{ id: 3, is_cooked: false, variant_id: 4307 }, { id: 4, is_cooked: true, variant_id: 99 }], user_meals: [] },
    ],
  };

  test('keeps live collections with their member ids', () => {
    assert.deepEqual(normalizeCollections(account), [{ name: 'Noodles', created_at: 5, recipe_ids: ['u-1'] }]);
  });

  test('counts plans and cooks per recipe, translating variant ids through favorites', () => {
    const history = normalizeHistory(account);
    const pub = history.find((h) => h.recipe_id === 'pub-1');
    assert.deepEqual(pub, { recipe_id: 'pub-1', planned: 2, cooked: 1, last_planned_at: 200 });
    assert.ok(history.find((h) => h.recipe_id === 'variant:99'));
    assert.ok(history.find((h) => h.recipe_id === 'u-1'));
  });
});

describe('manual grocery items from the web app', () => {
  test('recognizes is_user_created rows and keeps the section name as the aisle', () => {
    const items = extractManualItems({
      items: [
        { ingredient_name: 'coke zero', quantity: '', is_user_created: true, section: 'Other', ingredient_id: null },
        { ingredient_name: 'quinoa', quantity: '1 cup', is_user_created: false, section: 'Rice, Grains & Beans', ingredient_id: 5 },
      ],
    });
    assert.deepEqual(items, [{ name: 'coke zero', quantity: '', aisle: 'Other' }]);
  });
});
