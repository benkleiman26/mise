import { strict as assert } from 'node:assert';
import { test, describe } from 'node:test';
import { mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { entryNameFor, fetchFromZip, readStoredZip } from '../src/zipfetch.mjs';

/** Builds a stored zip the same way browser/rescue-images.js does. */
function storedZip(files) {
  const crcTable = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crcTable[n] = c >>> 0;
  }
  const crc32 = (buf) => {
    let c = 0xffffffff;
    for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const u16 = (v) => Buffer.from([v & 255, (v >> 8) & 255]);
  const u32 = (v) => Buffer.from([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >>> 24) & 255]);
  const parts = [];
  const central = [];
  let offset = 0;
  for (const [name, data] of files) {
    const n = Buffer.from(name);
    const crc = crc32(data);
    const local = Buffer.concat([Buffer.from([0x50, 0x4b, 3, 4]), u16(20), u16(0), u16(0), u16(0), u16(0), u32(crc), u32(data.length), u32(data.length), u16(n.length), u16(0)]);
    parts.push(local, n, data);
    central.push(Buffer.concat([Buffer.from([0x50, 0x4b, 1, 2]), u16(20), u16(20), u16(0), u16(0), u16(0), u16(0), u32(crc), u32(data.length), u32(data.length), u16(n.length), u16(0), u16(0), u16(0), u16(0), u32(0), u32(offset)]), n);
    offset += local.length + n.length + data.length;
  }
  const cdStart = offset;
  const cd = Buffer.concat(central);
  parts.push(cd, Buffer.concat([Buffer.from([0x50, 0x4b, 5, 6]), u16(0), u16(0), u16(files.length), u16(files.length), u32(cd.length), u32(cdStart), u16(0)]));
  return Buffer.concat(parts);
}

describe('zipfetch', () => {
  const files = [
    ['recipe/thumbnail/1/thumbnail_a.jpg', Buffer.from('jpeg-bytes')],
    ['user_recipes/2/presentation_b.png', Buffer.from('png-bytes')],
  ];

  test('reads every entry of a stored zip', () => {
    const entries = readStoredZip(storedZip(files));
    assert.equal(entries.size, 2);
    assert.equal(entries.get('recipe/thumbnail/1/thumbnail_a.jpg').toString(), 'jpeg-bytes');
  });

  test('maps a cdn-uploads url onto the entry name', () => {
    assert.equal(entryNameFor('https://cdn-uploads.mealime.com/uploads/user_recipes/2/presentation_b.png'), 'user_recipes/2/presentation_b.png');
  });

  test('answers like fetch, with a content type and a 404 for misses', async () => {
    const dir = await mkdtemp(path.join(tmpdir(), 'mise-zip-'));
    const file = path.join(dir, 'images.zip');
    await writeFile(file, storedZip(files));
    const fetchImpl = await fetchFromZip(file);
    const hit = await fetchImpl('https://cdn-uploads.mealime.com/uploads/user_recipes/2/presentation_b.png');
    assert.equal(hit.ok, true);
    assert.equal(hit.headers.get('content-type'), 'image/png');
    assert.equal(Buffer.from(await hit.arrayBuffer()).toString(), 'png-bytes');
    const miss = await fetchImpl('https://cdn-uploads.mealime.com/uploads/nope.jpg');
    assert.equal(miss.ok, false);
    assert.equal(miss.status, 404);
  });
});
