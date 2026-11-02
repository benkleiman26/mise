import { test } from 'node:test';
import assert from 'node:assert/strict';
import { convertRecipe, convertLibrary, minutesFromDuration, servingsFrom, stepsFrom, stripTags } from '../src/convert.mjs';
import { isAllowed, pickImageURL } from '../src/images.mjs';

const ld = (extra = {}) => ({
  '@type': 'Recipe',
  name: 'Lemon Garlic Butter Pasta',
  description: 'Five pantry things and one pot.',
  recipeYield: '4 servings',
  totalTime: 'PT20M',
  recipeIngredient: ['1 pound spaghetti', '4 garlic cloves, thinly sliced'],
  recipeInstructions: [{ '@type': 'HowToStep', text: 'Boil the pasta.' }],
  ...extra,
});

test('ISO durations become minutes', () => {
  assert.equal(minutesFromDuration('PT1H30M'), 90);
  assert.equal(minutesFromDuration('PT25M'), 25);
  assert.equal(minutesFromDuration('P1DT2H'), 1560);
  assert.equal(minutesFromDuration('nonsense'), 0);
  assert.equal(minutesFromDuration(undefined), 0);
});

test('servings are read from the ways NYT writes them', () => {
  assert.equal(servingsFrom('4 servings'), 4);
  assert.equal(servingsFrom('4 to 6 servings'), 4);
  assert.equal(servingsFrom(6), 6);
  assert.equal(servingsFrom('Serves a crowd'), null);
  assert.equal(servingsFrom(['8 servings']), 8);
});

test('instructions come out flat whichever shape they arrive in', () => {
  assert.deepEqual(stepsFrom(['One.', 'Two.']), ['One.', 'Two.']);
  assert.deepEqual(stepsFrom([{ '@type': 'HowToStep', text: 'One.' }]), ['One.']);
  assert.deepEqual(
    stepsFrom([{ '@type': 'HowToSection', itemListElement: [{ text: 'One.' }, { text: 'Two.' }] }, 'Three.']),
    ['One.', 'Two.', 'Three.']
  );
});

test('markup in the page does not reach the recipe', () => {
  assert.equal(stripTags('Heat <b>the</b> oven to 425&#39;'), "Heat the oven to 425'");
  assert.equal(stripTags('a&nbsp;&amp;&nbsp;b'), 'a & b');
});

test('a fetched recipe keeps its ingredient lines exactly as written', () => {
  const recipe = convertRecipe({ url: 'https://cooking.nytimes.com/recipes/1020052-lemon-pasta', jsonld: ld() });
  assert.equal(recipe.title, 'Lemon Garlic Butter Pasta');
  assert.equal(recipe.baseServings, 4);
  assert.deepEqual(recipe.ingredientLines, ['1 pound spaghetti', '4 garlic cloves, thinly sliced']);
  assert.deepEqual(recipe.steps, ['Boil the pasta.']);
  assert.equal(recipe.externalID, '1020052', 'the recipe id out of the url, so a retitle does not duplicate it');
});

test('a total time with no breakdown is not counted twice', () => {
  const recipe = convertRecipe({ url: 'https://cooking.nytimes.com/recipes/1-x', jsonld: ld({ prepTime: 'PT5M', totalTime: 'PT20M' }) });
  assert.equal(recipe.prepMinutes, 5);
  assert.equal(recipe.cookMinutes, 15, 'prep plus cook equals the total NYT published');
});

test('an explicit cook time wins over arithmetic', () => {
  const recipe = convertRecipe({ url: 'https://cooking.nytimes.com/recipes/1-x', jsonld: ld({ prepTime: 'PT5M', cookTime: 'PT30M', totalTime: 'PT35M' }) });
  assert.equal(recipe.cookMinutes, 30);
});

test('folders become tags and the cooked flag survives', () => {
  const recipe = convertRecipe({
    url: 'https://cooking.nytimes.com/recipes/1-x',
    folders: ['Weeknights', 'Pasta'],
    cooked: true,
    jsonld: ld(),
  });
  assert.deepEqual(recipe.tags, ['Weeknights', 'Pasta']);
  assert.equal(recipe.timesCooked, 1);
});

test('a page that had no recipe in it is skipped rather than imported blank', () => {
  assert.equal(convertRecipe({ url: 'https://cooking.nytimes.com/recipes/1-x', jsonld: null }), null);
  assert.equal(convertRecipe({ url: 'x', jsonld: { '@type': 'Recipe', name: '' } }), null);
  assert.equal(convertRecipe({ url: 'x', jsonld: { '@type': 'Recipe', name: 'Empty' } }), null);
});

test('the library comes out sorted, deduplicated and reported on', () => {
  const { document, report } = convertLibrary([
    { url: 'https://cooking.nytimes.com/recipes/2-zed', jsonld: ld({ name: 'Zed' }) },
    { url: 'https://cooking.nytimes.com/recipes/1-abel', jsonld: ld({ name: 'Abel' }), cooked: true },
    { url: 'https://cooking.nytimes.com/recipes/1-abel-again', jsonld: ld({ name: 'Abel again' }) },
    { url: 'https://cooking.nytimes.com/recipes/3-broken', jsonld: null },
  ]);

  assert.deepEqual(document.recipes.map((r) => r.title), ['Abel', 'Zed']);
  assert.equal(document.source, 'nyt');
  assert.equal(document.format, 'mise-recipe-import');
  assert.equal(report.converted, 2);
  assert.equal(report.skipped.length, 2, 'one duplicate id, one unreadable page');
  assert.equal(report.cooked, 1);
});

// Photos.

test('only NYT image hosts over https are fetched', () => {
  assert.equal(isAllowed('https://static01.nyt.com/images/a.jpg'), true);
  assert.equal(isAllowed('https://cooking.nytimes.com/a.jpg'), true);
  assert.equal(isAllowed('http://static01.nyt.com/images/a.jpg'), false, 'plain http is refused');
  assert.equal(isAllowed('https://example.com/a.jpg'), false);
  assert.equal(isAllowed('not a url'), false);
  assert.equal(isAllowed(undefined), false);
});

test('the big size wins over the thumbnail', () => {
  assert.equal(
    pickImageURL([
      'https://static01.nyt.com/images/a-thumbStandard.jpg',
      'https://static01.nyt.com/images/a-superJumbo.jpg',
      'https://static01.nyt.com/images/a-articleLarge.jpg',
    ]),
    'https://static01.nyt.com/images/a-superJumbo.jpg'
  );
});

test('with nothing in the names, the first wins, because JSON-LD leads with the primary image', () => {
  assert.equal(
    pickImageURL(['https://static01.nyt.com/images/one.jpg', 'https://static01.nyt.com/images/two.jpg']),
    'https://static01.nyt.com/images/one.jpg'
  );
});

test('a recipe with no usable image url downloads nothing rather than guessing', () => {
  assert.equal(pickImageURL([]), null);
  assert.equal(pickImageURL(['https://example.com/a.jpg']), null);
  assert.equal(pickImageURL(undefined), null);
});
