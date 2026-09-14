import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { mkdtemp, readFile, rm, writeFile, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import {
  attachLocalPaths,
  downloadOne,
  extensionFor,
  imageTargets,
  pool,
  runImages,
  safeName,
} from '../src/images.mjs';

/** Minimal stand in for fetch, so the download path is tested without network. */
function stubFetch(routes) {
  return async (url) => {
    const route = routes[url];
    if (!route) return { ok: false, status: 404, headers: { get: () => null } };
    if (route.throws) throw new Error(route.throws);
    return {
      ok: true,
      status: 200,
      headers: { get: (k) => (k.toLowerCase() === 'content-type' ? route.type : null) },
      arrayBuffer: async () => route.body,
    };
  };
}

const PIXEL = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]).buffer;

describe('extensionFor', () => {
  test('prefers the content type the server sent', () => {
    assert.equal(extensionFor('image/png', 'https://a.test/x.jpg'), '.png');
    assert.equal(extensionFor('image/jpeg; charset=binary', 'https://a.test/x'), '.jpg');
  });

  test('falls back to the url when the content type is useless', () => {
    assert.equal(extensionFor('application/octet-stream', 'https://a.test/x.webp'), '.webp');
    assert.equal(extensionFor(null, 'https://a.test/x.jpeg'), '.jpg');
  });

  test('has a safe default', () => {
    assert.equal(extensionFor(null, 'https://a.test/photo'), '.img');
    assert.equal(extensionFor(null, 'not a url'), '.img');
  });
});

describe('safeName', () => {
  test('keeps ids usable as directory names', () => {
    assert.equal(safeName('abc-123'), 'abc-123');
    assert.equal(safeName('a/b'), 'a%2Fb');
  });
});

describe('imageTargets', () => {
  test('covers both full recipes and withheld references', () => {
    const targets = imageTargets([
      { mealime_id: 'a', images: ['https://a.test/1.jpg', 'https://a.test/2.jpg'] },
      { mealime_id: 'b', image: 'https://a.test/3.jpg' },
    ]);
    assert.equal(targets.length, 3);
    assert.deepEqual(targets[1], { recipeId: 'a', url: 'https://a.test/2.jpg', index: 1 });
  });

  test('ignores anything that is not an http url', () => {
    assert.deepEqual(imageTargets([{ mealime_id: 'a', images: [null, 'data:image/png;base64,xx'] }]), []);
  });
});

describe('pool', () => {
  test('runs everything and never exceeds the limit', async () => {
    let inFlight = 0;
    let peak = 0;
    const results = await pool([1, 2, 3, 4, 5, 6, 7], 3, async (n) => {
      inFlight += 1;
      peak = Math.max(peak, inFlight);
      await new Promise((r) => setTimeout(r, 1));
      inFlight -= 1;
      return n * 2;
    });
    assert.deepEqual(results, [2, 4, 6, 8, 10, 12, 14]);
    assert.ok(peak <= 3, `peak concurrency was ${peak}`);
  });

  test('copes with an empty list', async () => {
    assert.deepEqual(await pool([], 4, async () => 1), []);
  });
});

describe('downloadOne', () => {
  test('saves the bytes under the recipe id', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'img-'));
    const result = await downloadOne(
      { recipeId: 'abc', url: 'https://a.test/1.jpg', index: 0 },
      { dir, fetchImpl: stubFetch({ 'https://a.test/1.jpg': { type: 'image/png', body: PIXEL } }) }
    );
    assert.equal(result.status, 'downloaded');
    assert.equal(path.basename(result.file), '0.png');
    assert.equal((await readFile(result.file)).byteLength, 8);
    await rm(dir, { recursive: true, force: true });
  });

  test('skips a file it already has, so a run can resume', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'img-'));
    await mkdir(path.join(dir, 'abc'), { recursive: true });
    await writeFile(path.join(dir, 'abc', '0.png'), Buffer.from([1, 2, 3]));
    const result = await downloadOne(
      { recipeId: 'abc', url: 'https://a.test/1.jpg', index: 0 },
      { dir, fetchImpl: () => assert.fail('should not have fetched') }
    );
    assert.equal(result.status, 'skipped');
    await rm(dir, { recursive: true, force: true });
  });

  test('reports a dead url instead of throwing, so one failure does not stop the rescue', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'img-'));
    const missing = await downloadOne(
      { recipeId: 'abc', url: 'https://a.test/gone.jpg', index: 0 },
      { dir, fetchImpl: stubFetch({}) }
    );
    assert.equal(missing.status, 'failed');
    assert.equal(missing.error, 'HTTP 404');

    const broken = await downloadOne(
      { recipeId: 'abc', url: 'https://a.test/x.jpg', index: 0 },
      { dir, fetchImpl: stubFetch({ 'https://a.test/x.jpg': { throws: 'socket hang up' } }) }
    );
    assert.equal(broken.status, 'failed');
    assert.equal(broken.error, 'socket hang up');
    await rm(dir, { recursive: true, force: true });
  });
});

describe('attachLocalPaths', () => {
  test('records paths relative to the export directory', () => {
    const out = attachLocalPaths(
      [{ mealime_id: 'a' }, { mealime_id: 'b' }],
      [{ recipeId: 'a', index: 0, status: 'downloaded', file: '/out/images/a/0.jpg' }],
      '/out'
    );
    assert.deepEqual(out[0].local_images, ['images/a/0.jpg']);
    assert.equal(out[1].local_images, undefined);
  });

  test('leaves out failures', () => {
    const out = attachLocalPaths(
      [{ mealime_id: 'a' }],
      [{ recipeId: 'a', index: 0, status: 'failed', file: undefined }],
      '/out'
    );
    assert.equal(out[0].local_images, undefined);
  });
});

describe('runImages', () => {
  test('downloads, records paths in the bundle, and counts failures', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'export-'));
    await mkdir(path.join(dir, 'recipes'), { recursive: true });
    const bundle = {
      format: 'mealime-export',
      version: 1,
      counts: {},
      recipes: [{ mealime_id: 'own', name: 'Mine', images: ['https://a.test/1.jpg'] }],
      withheld: [{ mealime_id: 'theirs', name: 'Theirs', image: 'https://a.test/dead.jpg' }],
    };
    await writeFile(path.join(dir, 'mealime-export.json'), JSON.stringify(bundle));
    await writeFile(path.join(dir, 'recipes', 'own.json'), JSON.stringify({ mealime_id: 'own', name: 'Mine' }));

    const summary = await runImages({
      outDir: dir,
      fetchImpl: stubFetch({ 'https://a.test/1.jpg': { type: 'image/jpeg', body: PIXEL } }),
      log: () => {},
    });

    assert.equal(summary.downloaded, 1);
    assert.equal(summary.failed.length, 1);

    const written = JSON.parse(await readFile(path.join(dir, 'mealime-export.json'), 'utf8'));
    assert.deepEqual(written.recipes[0].local_images, ['images/own/0.jpg']);
    assert.equal(written.withheld[0].local_images, undefined);
    assert.equal(written.counts.imagesDownloaded, 1);
    assert.equal(written.counts.imagesFailed, 1);

    const perRecipe = JSON.parse(await readFile(path.join(dir, 'recipes', 'own.json'), 'utf8'));
    assert.deepEqual(perRecipe.local_images, ['images/own/0.jpg']);

    await rm(dir, { recursive: true, force: true });
  });

  test('refuses to run before the export exists', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'export-'));
    await assert.rejects(() => runImages({ outDir: dir, log: () => {} }), /Run the export and normalize steps first/);
    await rm(dir, { recursive: true, force: true });
  });
});
