// A fetch() stand-in that answers from a zip file on disk.
//
// Mealime's image host (cdn-uploads.mealime.com) only serves the owner's
// browser: Node from a laptop and from a cloud shell both get 403 or a refused
// connection. So the browser fetches every image itself and packs them into a
// stored (uncompressed) zip whose entry names are the URL paths under
// /uploads/. This module lets `images --from-zip` reuse the normal download
// code by pretending the zip is the network.
//
// Only the stored method (0) is supported. That is what the browser script
// writes, and it keeps this file dependency free.

import { readFile } from 'node:fs/promises';

const SIG_EOCD = 0x06054b50;
const SIG_CENTRAL = 0x02014b50;
const SIG_LOCAL = 0x04034b50;

/** Reads the central directory of a stored zip into a name to slice map. */
export function readStoredZip(buffer) {
  let eocd = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 65558); i--) {
    if (buffer.readUInt32LE(i) === SIG_EOCD) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw new Error('not a zip file: no end of central directory');
  const entryCount = buffer.readUInt16LE(eocd + 10);
  let cursor = buffer.readUInt32LE(eocd + 16);
  const entries = new Map();
  for (let n = 0; n < entryCount; n++) {
    if (buffer.readUInt32LE(cursor) !== SIG_CENTRAL) throw new Error('corrupt central directory');
    const method = buffer.readUInt16LE(cursor + 10);
    const size = buffer.readUInt32LE(cursor + 24);
    const nameLength = buffer.readUInt16LE(cursor + 28);
    const extraLength = buffer.readUInt16LE(cursor + 30);
    const commentLength = buffer.readUInt16LE(cursor + 32);
    const offset = buffer.readUInt32LE(cursor + 42);
    const name = buffer.subarray(cursor + 46, cursor + 46 + nameLength).toString('utf8');
    if (method !== 0) throw new Error(`entry ${name} is compressed; only stored zips are supported`);
    if (buffer.readUInt32LE(offset) !== SIG_LOCAL) throw new Error(`corrupt local header for ${name}`);
    const localNameLength = buffer.readUInt16LE(offset + 26);
    const localExtraLength = buffer.readUInt16LE(offset + 28);
    const start = offset + 30 + localNameLength + localExtraLength;
    entries.set(name, buffer.subarray(start, start + size));
    cursor += 46 + nameLength + extraLength + commentLength;
  }
  return entries;
}

const TYPE_BY_EXTENSION = {
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.webp': 'image/webp',
  '.gif': 'image/gif',
};

/** Maps a cdn-uploads URL onto the entry name the browser script used. */
export function entryNameFor(url) {
  const { pathname } = new URL(url);
  return decodeURIComponent(pathname.replace(/^\/uploads\//, ''));
}

/** Builds a fetch-compatible function over the zip's entries. */
export async function fetchFromZip(zipFile) {
  const entries = readStoredZip(await readFile(zipFile));
  return async function fetchImpl(url) {
    const name = entryNameFor(url);
    const data = entries.get(name);
    if (!data) return { ok: false, status: 404, headers: { get: () => null } };
    const ext = name.slice(name.lastIndexOf('.')).toLowerCase();
    return {
      ok: true,
      status: 200,
      headers: { get: (key) => (key.toLowerCase() === 'content-type' ? TYPE_BY_EXTENSION[ext] ?? null : null) },
      arrayBuffer: async () => data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength),
    };
  };
}
