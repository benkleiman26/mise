import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';

import { ReadOnlyClient, ReadOnlyViolation, authHeaders, backoffMs, retryAfterMs } from '../src/http.mjs';
import { diagnose, extractCollection, nextPage, summarize } from '../src/discover.mjs';
import { chooseCandidate, recipeId } from '../src/export.mjs';

describe('read only guards', () => {
  const client = new ReadOnlyClient({ token: 'test-token' });

  test('refuses any method that could change the account', () => {
    for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
      assert.throws(
        () => client.assertSafe('https://api.mealime.com/api/v2/recipes', method),
        ReadOnlyViolation,
        `${method} should be refused`
      );
    }
  });

  test('allows GET and HEAD against mealime hosts', () => {
    assert.doesNotThrow(() => client.assertSafe('https://api.mealime.com/api/v2/recipes', 'GET'));
    assert.doesNotThrow(() => client.assertSafe('https://my.mealime.com/recipes', 'HEAD'));
  });

  test('refuses to send the token to any other host', () => {
    assert.throws(() => client.assertSafe('https://evil.test/collect', 'GET'), ReadOnlyViolation);
  });

  test('requires a token', () => {
    assert.throws(() => new ReadOnlyClient({ token: '' }), /Missing auth token/);
  });
});

describe('authHeaders', () => {
  test('covers the schemes we probe', () => {
    assert.deepEqual(authHeaders('t', 'bearer'), { authorization: 'Bearer t' });
    assert.deepEqual(authHeaders('t', 'x-auth-token'), { 'x-auth-token': 't' });
    assert.deepEqual(authHeaders('t', 'query'), {});
    assert.throws(() => authHeaders('t', 'nope'), /Unknown auth scheme/);
  });
});

describe('backoff', () => {
  test('grows and caps', () => {
    assert.equal(backoffMs(0), 1000);
    assert.equal(backoffMs(3), 8000);
    assert.equal(backoffMs(9), 16000);
  });

  test('honours Retry-After in seconds and as a date', () => {
    assert.equal(retryAfterMs('2'), 2000);
    assert.equal(retryAfterMs(null), null);
    const soon = new Date(Date.now() + 5000).toUTCString();
    assert.ok(retryAfterMs(soon) > 1000);
  });
});

describe('extractCollection', () => {
  test('unwraps the usual envelopes', () => {
    assert.deepEqual(extractCollection([1, 2]), [1, 2]);
    assert.deepEqual(extractCollection({ data: [1] }), [1]);
    assert.deepEqual(extractCollection({ recipes: [1, 2, 3] }), [1, 2, 3]);
  });

  test('falls back to a lone array property', () => {
    assert.deepEqual(extractCollection({ weird_key: [1], total: 1 }), [1]);
  });

  test('gives up when the shape is ambiguous', () => {
    assert.equal(extractCollection({ a: [1], b: [2] }), null);
    assert.equal(extractCollection(null), null);
  });
});

describe('nextPage', () => {
  const base = 'https://api.mealime.com/api/v2/recipes?page=1';

  test('follows an absolute or relative next link', () => {
    assert.equal(nextPage({ next: 'https://api.mealime.com/x' }, base), 'https://api.mealime.com/x');
    assert.equal(nextPage({ links: { next: '/api/v2/recipes?page=2' } }, base), 'https://api.mealime.com/api/v2/recipes?page=2');
  });

  test('builds a page query when given only a page number', () => {
    assert.equal(nextPage({ meta: { next_page: 3 } }, base), 'https://api.mealime.com/api/v2/recipes?page=3');
  });

  test('returns null at the end', () => {
    assert.equal(nextPage({ next: null }, base), null);
    assert.equal(nextPage({}, base), null);
  });
});

describe('recipeId', () => {
  test('prefers stable identifiers and accepts numbers', () => {
    assert.equal(recipeId({ uuid: 'u', id: 7 }), 'u');
    assert.equal(recipeId({ id: 7 }), '7');
    assert.equal(recipeId({ nothing: true }), null);
  });
});

describe('chooseCandidate', () => {
  test('picks the endpoint that returned the most records', () => {
    const chosen = chooseCandidate([
      { path: '/a', ok: true, count: 3 },
      { path: '/b', ok: true, count: 150 },
      { path: '/c', ok: false, count: null },
    ]);
    assert.equal(chosen.path, '/b');
  });

  test('returns null when nothing is usable', () => {
    assert.equal(chooseCandidate([{ path: '/a', ok: false, count: null }]), null);
  });
});

describe('summarize', () => {
  test('reports counts for collections and keys otherwise', () => {
    assert.equal(summarize({ status: 200, json: [1, 2] }).count, 2);
    assert.equal(summarize({ status: 200, json: { a: 1, b: 2 } }).count, null);
    assert.equal(summarize({ status: 401, json: null }).ok, false);
  });
});

describe('diagnose', () => {
  test('blames the routes, not the token, when everything is a 404', () => {
    const message = diagnose({ 404: 30 });
    assert.match(message, /paths are wrong, not the token/);
    assert.match(message, /capture-api-calls/);
  });

  test('blames the token when the server actively rejects it', () => {
    assert.match(diagnose({ 401: 6, 404: 24 }), /rejected the token/);
    assert.match(diagnose({ 403: 30 }), /rejected the token/);
  });

  test('calls out a network problem', () => {
    assert.match(diagnose({ 0: 30 }), /network level/);
    assert.match(diagnose({}), /No requests completed/);
  });

  test('calls out a server problem', () => {
    assert.match(diagnose({ 503: 30 }), /returning errors/);
  });

  test('asks for the output when it cannot tell', () => {
    assert.match(diagnose({ 302: 30 }), /Send this output in/);
  });
});
