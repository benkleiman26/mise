// Mealime's v2 API is not publicly documented and we cannot test it without the
// owner's account, so the export does not hard code routes. It probes a list of
// plausible candidates, reports what answers, and writes the result to
// _discovery.json. The export step then uses whatever was found.
//
// If every candidate fails, use the browser fallback in ../browser/.

import { AUTH_SCHEMES, ReadOnlyClient } from './http.mjs';

export const DEFAULT_BASE = 'https://api.mealime.com/api/v2';

/** Cheap endpoints used to work out which auth scheme the server accepts. */
export const IDENTITY_CANDIDATES = [
  '/users/me',
  '/user',
  '/me',
  '/account',
  '/users/current',
  '/profile',
];

/**
 * Endpoints that return a single object rather than a collection. Preferences
 * matter because section 5.7 exports the user's eating preferences alongside
 * their recipes, so a Mealime user lands in Mise already set up.
 */
export const SINGLETON_CANDIDATES = {
  preferences: [
    '/users/me/preferences',
    '/preferences',
    '/dietary_preferences',
    '/settings',
    '/users/me/settings',
  ],
};

/** Collection endpoints, grouped by the role they play in the export. */
export const COLLECTION_CANDIDATES = {
  favorites: [
    '/recipes/favorites',
    '/favorites',
    '/favorite_recipes',
    '/users/me/favorites',
    '/recipes?favorited=true',
  ],
  userRecipes: [
    '/user_recipes',
    '/recipes/mine',
    '/recipes?owned=true',
    '/users/me/recipes',
    '/imported_recipes',
    '/recipes',
  ],
  mealPlans: ['/meal_plans', '/plans', '/users/me/meal_plans'],
  groceryLists: ['/grocery_lists', '/shopping_lists', '/grocery_list', '/users/me/grocery_lists'],
};

function looksAuthenticated(response) {
  return response.status === 200 && response.json !== null;
}

/**
 * Tries each auth scheme against each identity endpoint until one returns 200
 * with a JSON body.
 *
 * On failure it reports why, because the two causes need different fixes and
 * look identical from the outside. A rejected token returns 401 or 403 and is
 * fixed by copying a fresh one. Routes that do not exist return 404 for every
 * scheme, and no token will ever fix that: the paths below are guesses and the
 * real ones have to be captured from the web app. See
 * browser/capture-api-calls.js.
 */
export async function resolveAuthScheme({ token, base = DEFAULT_BASE, log = () => {} }) {
  const statusCounts = {};
  for (const scheme of AUTH_SCHEMES) {
    const client = new ReadOnlyClient({ token, scheme, log });
    for (const path of IDENTITY_CANDIDATES) {
      const response = await client.get(base + path);
      statusCounts[response.status] = (statusCounts[response.status] ?? 0) + 1;
      log(`  ${scheme.padEnd(13)} GET ${path} -> ${response.status}`);
      if (looksAuthenticated(response)) {
        return { ok: true, scheme, identityPath: path, identity: response.json };
      }
    }
  }
  return { ok: false, statusCounts, diagnosis: diagnose(statusCounts, base) };
}

/** Turns a spread of response codes into the one sentence that matters. */
export function diagnose(statusCounts, base = DEFAULT_BASE) {
  const codes = Object.keys(statusCounts).map(Number);
  const total = Object.values(statusCounts).reduce((a, b) => a + b, 0);

  if (total === 0) return 'No requests completed. Check your network connection.';
  if (codes.every((c) => c === 0)) {
    return 'Every request failed at the network level. Check your connection, or whether a VPN or proxy is blocking mealime.com.';
  }
  if (codes.every((c) => c === 404)) {
    return (
      `Every route under ${base} returned 404, under every auth scheme. That means the ` +
      'paths are wrong, not the token, and a fresh token will not help. Capture the real ' +
      'routes with browser/capture-api-calls.js and send them in, or open an issue with the output.'
    );
  }
  if (codes.some((c) => c === 401 || c === 403)) {
    return (
      'The server rejected the token. Copy a fresh one from the browser: it is short lived. ' +
      'See "Getting your token" in README.md.'
    );
  }
  if (codes.some((c) => c >= 500)) {
    return 'The server is returning errors. Wait a few minutes and try again.';
  }
  return `Unexpected responses: ${JSON.stringify(statusCounts)}. Send this output in.`;
}

/**
 * Probes every collection candidate with a known good auth scheme and records
 * the outcome. Every candidate is tried, not just the first hit, because the
 * shapes tell us which route actually holds the recipes.
 */
export async function probeCollections({ client, base = DEFAULT_BASE, log = () => {} }) {
  const results = {};
  for (const [role, paths] of Object.entries(COLLECTION_CANDIDATES)) {
    results[role] = [];
    for (const path of paths) {
      const response = await client.get(base + path);
      const summary = summarize(response);
      log(`  ${role.padEnd(13)} GET ${path} -> ${response.status} ${summary.hint}`);
      results[role].push({ path, status: response.status, ...summary });
    }
  }
  return results;
}

/** Probes the singleton endpoints and keeps the first that answers with JSON. */
export async function probeSingletons({ client, base = DEFAULT_BASE, log = () => {} }) {
  const found = {};
  for (const [role, paths] of Object.entries(SINGLETON_CANDIDATES)) {
    for (const path of paths) {
      const response = await client.get(base + path);
      log(`  ${role.padEnd(13)} GET ${path} -> ${response.status}`);
      if (response.status === 200 && response.json !== null) {
        found[role] = { path, body: response.json };
        break;
      }
    }
  }
  return found;
}

/** Describes a response well enough to choose between candidates by eye. */
export function summarize(response) {
  if (response.json === null) {
    return { ok: false, count: null, keys: [], hint: response.status === 200 ? '(not JSON)' : '' };
  }
  const collection = extractCollection(response.json);
  const keys = Array.isArray(response.json) ? [] : Object.keys(response.json).slice(0, 12);
  return {
    ok: response.status === 200,
    count: collection ? collection.length : null,
    keys,
    hint: collection ? `(${collection.length} items)` : `(keys: ${keys.slice(0, 5).join(', ')})`,
  };
}

/**
 * Pulls the array out of a JSON response. APIs wrap collections in all sorts of
 * envelopes, so try the body itself, then the common wrapper keys, then any
 * single array-valued property.
 */
export function extractCollection(body) {
  if (Array.isArray(body)) return body;
  if (!body || typeof body !== 'object') return null;
  for (const key of ['data', 'results', 'items', 'recipes', 'favorites', 'records', 'entries']) {
    if (Array.isArray(body[key])) return body[key];
  }
  const arrays = Object.values(body).filter(Array.isArray);
  return arrays.length === 1 ? arrays[0] : null;
}

/** Finds the next page URL or cursor, covering the usual pagination styles. */
export function nextPage(body, currentUrl) {
  if (!body || typeof body !== 'object') return null;
  const direct = body.next || body.next_url || body.next_page_url;
  if (typeof direct === 'string' && direct) return absolute(direct, currentUrl);
  const links = body.links || body.meta || body.pagination || {};
  const nested = links.next || links.next_url || links.next_page_url;
  if (typeof nested === 'string' && nested) return absolute(nested, currentUrl);
  const nextNumber = links.next_page ?? body.next_page;
  if (Number.isInteger(nextNumber) && nextNumber > 0) {
    const url = new URL(currentUrl);
    url.searchParams.set('page', String(nextNumber));
    return url.toString();
  }
  return null;
}

function absolute(href, base) {
  try {
    return new URL(href, base).toString();
  } catch {
    return null;
  }
}
