import { test } from 'node:test';
import assert from 'node:assert/strict';
import { convertRecipe, convertLibrary, ingredientLine, isJunk, stepText } from '../src/convert.mjs';
import { pickPhoto } from '../src/images.mjs';

// The two shapes in the real export: a recipe the owner imported, where the
// whole line sits in ingredient_name, and one Mealime published, where the
// quantity is its own field.

test('an owner imported line is kept exactly as written', () => {
  assert.equal(
    ingredientLine({ quantity: '', ingredient_name: '2 scallions, trimmed then sliced', raw: '2 scallions, trimmed then sliced' }),
    '2 scallions, trimmed then sliced'
  );
});

test('a separate quantity is joined back onto the name', () => {
  assert.equal(ingredientLine({ quantity: '2 tbsp', ingredient_name: 'olive oil', raw: 'olive oil' }), '2 tbsp olive oil');
});

test('a quantity already inside the name is not repeated', () => {
  assert.equal(ingredientLine({ quantity: '2 tbsp', ingredient_name: '2 tbsp olive oil', raw: '' }), '2 tbsp olive oil');
});

test('raw wins when it already carries the quantity', () => {
  assert.equal(ingredientLine({ quantity: '1 lb', ingredient_name: 'cucumbers', raw: '1 lb cucumbers (such as 6 Persian)' }), '1 lb cucumbers (such as 6 Persian)');
});

test('a line with nothing in it comes out empty', () => {
  assert.equal(ingredientLine({ quantity: '', ingredient_name: '', raw: '' }), '');
  assert.equal(ingredientLine(null), '');
});

test('a step keeps its aside', () => {
  assert.equal(stepText({ primary_message: 'Heat the oven.', secondary_message: 'To 425F.' }), 'Heat the oven. To 425F.');
  assert.equal(stepText({ primary_message: 'Heat the oven.', secondary_message: '' }), 'Heat the oven.');
});

test('steps come out in position order, not file order', () => {
  const recipe = convertRecipe({
    name: 'Something',
    line_items: [{ raw: 'salt' }],
    instructions: [
      { position: 3, primary_message: 'Third.' },
      { position: 1, primary_message: 'First.' },
      { position: 2, primary_message: 'Second.' },
    ],
  });
  assert.deepEqual(recipe.steps, ['First.', 'Second.', 'Third.']);
});

test('a null serving count falls back and a null cooking time stays zero', () => {
  const recipe = convertRecipe({ name: 'Salad', serving_count: null, cooking_minutes: null, line_items: [{ raw: 'lettuce' }] });
  assert.equal(recipe.baseServings, 4);
  assert.equal(recipe.cookMinutes, 0);
});

test('a recorded serving count and cooking time are kept', () => {
  const recipe = convertRecipe({ name: 'Stew', serving_count: 6, cooking_minutes: 45, line_items: [{ raw: 'beef' }] });
  assert.equal(recipe.baseServings, 6);
  assert.equal(recipe.cookMinutes, 45);
});

test('a recipe with no title is skipped rather than imported blank', () => {
  assert.equal(convertRecipe({ name: '', line_items: [{ raw: 'salt' }] }), null);
});

test('a recipe with neither ingredients nor steps is skipped', () => {
  assert.equal(convertRecipe({ name: 'Empty', line_items: [], instructions: [] }), null);
});

test('a recipe with steps but no ingredients is still worth keeping', () => {
  const recipe = convertRecipe({ name: 'Method only', instructions: [{ position: 1, primary_message: 'Stir.' }] });
  assert.equal(recipe.title, 'Method only');
  assert.deepEqual(recipe.ingredientLines, []);
});

test('blank ingredient lines are dropped, not imported as empty rows', () => {
  const recipe = convertRecipe({
    name: 'Something',
    line_items: [{ raw: 'salt' }, { raw: '   ' }, { quantity: '', ingredient_name: '' }],
  });
  assert.deepEqual(recipe.ingredientLines, ['salt']);
});

test('collections become tags', () => {
  const recipe = convertRecipe({
    name: 'Something',
    line_items: [{ raw: 'salt' }],
    collections: ['Weeknights', { name: 'Favourites' }, 'Weeknights'],
  });
  assert.deepEqual(recipe.tags, ['Weeknights', 'Favourites']);
});

test('only http image urls survive', () => {
  const recipe = convertRecipe({
    name: 'Something',
    line_items: [{ raw: 'salt' }],
    images: ['https://cdn-uploads.mealime.com/a.jpg', null, 'not a url', 42],
  });
  assert.deepEqual(recipe.imageURLs, ['https://cdn-uploads.mealime.com/a.jpg']);
});

test('the library comes out sorted, deduplicated, and reported on', () => {
  const { document, report } = convertLibrary([
    { file: 'b.json', recipe: { mealime_id: 'b', name: 'Beans', line_items: [{ raw: 'beans' }] } },
    { file: 'a.json', recipe: { mealime_id: 'a', name: 'Apples', line_items: [{ raw: 'apples' }], cooking_minutes: 10 } },
    { file: 'b2.json', recipe: { mealime_id: 'b', name: 'Beans again', line_items: [{ raw: 'beans' }] } },
    { file: 'empty.json', recipe: { name: '' } },
  ]);

  assert.deepEqual(document.recipes.map((r) => r.title), ['Apples', 'Beans']);
  assert.equal(document.format, 'mise-recipe-import');
  assert.equal(report.read, 4);
  assert.equal(report.converted, 2);
  assert.equal(report.skipped.length, 2);
  assert.equal(report.withoutCookTime, 1);
  assert.equal(report.ingredientLines, 2);
});

test('a recipe with no id is deduplicated by title instead', () => {
  const { document, report } = convertLibrary([
    { file: 'a.json', recipe: { name: 'Toast', line_items: [{ raw: 'bread' }] } },
    { file: 'b.json', recipe: { name: 'toast', line_items: [{ raw: 'bread' }] } },
  ]);
  assert.equal(document.recipes.length, 1);
  assert.equal(report.skipped.length, 1);
});

// Mealime's "import from a link" captured whatever the page had where the
// ingredients were. Twenty or so of the owner's 2436 lines are page furniture.

test('page furniture is dropped', () => {
  for (const line of [
    '^ Back to Top',
    'Recent Posts',
    'Pinch of Yum logo',
    'Mobile Search Trigger',
    '5 (from 113 ratings)',
    'February 9',
    'Toppings',
    'Remaining Ingredients',
    '<a href="https://cooking.nytimes.com/recipes/1015987"><span>Marinara</span></a>',
    'Ingredients2 1/2 cups vegetable broth1/2 cup uncooked quinoa',
    '▢ 2 large cucumbers ▢ 1 cup sushi rice',
    '   ',
    '1/2',
  ]) {
    assert.equal(isJunk(line), true, `${line} should be dropped`);
  }
});

test('real ingredients are never dropped, including the odd looking ones', () => {
  for (const line of [
    '2 scallions, trimmed',
    'Salt and pepper',
    'Ice',
    'Oil',
    '1 (15-ounce) can of black beans',
    'Toppings : toasted nuts or seeds',
    'Lemon wedges for serving',
    'Nước chấm or peanut sauce',
    "dozen Hershey's Kisses",
    '2 tablespoons extra-virgin olive oil',
  ]) {
    assert.equal(isJunk(line), false, `${line} should be kept`);
  }
});

test('the junk a conversion dropped is counted', () => {
  const { document, report } = convertLibrary([
    { file: 'a.json', recipe: { mealime_id: 'a', name: 'Soup', line_items: [
      { raw: '1 onion' }, { raw: 'Recent Posts' }, { raw: '^ Back to Top' },
    ] } },
  ]);
  assert.deepEqual(document.recipes[0].ingredientLines, ['1 onion']);
  assert.equal(report.junkDropped, 2);
});

// Photos: one per recipe, the big one rather than the thumbnail.

test('the presentation photo wins over the thumbnail', () => {
  const chosen = pickPhoto([
    { name: 'thumbnail_abc.jpg', size: 9000 },
    { name: 'presentation_abc.jpg', size: 4000 },
  ]);
  assert.equal(chosen.name, 'presentation_abc.jpg', 'even though it is the smaller file');
});

test('with nothing in the names, the biggest file wins', () => {
  const chosen = pickPhoto([
    { name: 'a.jpg', size: 1000 },
    { name: 'b.jpg', size: 9000 },
  ]);
  assert.equal(chosen.name, 'b.jpg');
});

test('files that are not pictures are never chosen', () => {
  assert.equal(pickPhoto([{ name: 'notes.txt', size: 99999 }]), null);
  assert.equal(pickPhoto([]), null);
  assert.equal(
    pickPhoto([{ name: 'notes.txt', size: 99999 }, { name: 'a.png', size: 10 }]).name,
    'a.png'
  );
});
