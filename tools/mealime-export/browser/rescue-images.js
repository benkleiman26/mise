// Mealime image rescue.
//
// cdn-uploads.mealime.com (the recipe photos) answers only the owner's browser.
// Node gets 403, and the pages on my.mealime.com cannot fetch it either because
// it sends no CORS headers. A tab that is ON that origin can, so:
//
//   1. Run `node src/cli.mjs image-paths > paths.json` after normalize.
//   2. Open any image from the export in a tab, for example
//      https://cdn-uploads.mealime.com/uploads/recipe/thumbnail/534/thumbnail_f57e494e-7e4c-435c-a3a4-a653dfdcd7a1.jpg
//   3. Paste this file into the console, then paste the contents of paths.json
//      as `__miseImages.rescue(<paste>)`.
//   4. Click the green button that appears. Chrome wants a real click for a
//      download from a page that is not HTML. It saves mealime-images.zip.
//   5. Back in a terminal: node src/cli.mjs images --from-zip ~/Downloads/mealime-images.zip
//
// The zip is stored, not compressed (photos do not compress), and is written by
// hand so that nothing needs to be loaded from a third party into the page.

(() => {
  const crcTable = (() => {
    const t = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      t[n] = c >>> 0;
    }
    return t;
  })();
  const crc32 = (buf) => {
    let c = 0xffffffff;
    for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
    return (c ^ 0xffffffff) >>> 0;
  };
  const u16 = (v) => [v & 255, (v >> 8) & 255];
  const u32 = (v) => [v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >>> 24) & 255];
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function storedZip(files) {
    const enc = new TextEncoder();
    const parts = [];
    const central = [];
    let offset = 0;
    for (const f of files) {
      const name = enc.encode(f.name);
      const crc = crc32(f.data);
      const size = f.data.length;
      const local = new Uint8Array([0x50, 0x4b, 3, 4, ...u16(20), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(crc), ...u32(size), ...u32(size), ...u16(name.length), ...u16(0)]);
      parts.push(local, name, f.data);
      central.push(new Uint8Array([0x50, 0x4b, 1, 2, ...u16(20), ...u16(20), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(crc), ...u32(size), ...u32(size), ...u16(name.length), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(0), ...u32(offset)]), name);
      offset += local.length + name.length + size;
    }
    let cdSize = 0;
    for (const c of central) {
      parts.push(c);
      cdSize += c.length;
    }
    parts.push(new Uint8Array([0x50, 0x4b, 5, 6, ...u16(0), ...u16(0), ...u16(files.length), ...u16(files.length), ...u32(cdSize), ...u32(offset), ...u16(0)]));
    return new Blob(parts, { type: 'application/zip' });
  }

  async function rescue(paths, { concurrency = 3, delayMs = 100 } = {}) {
    if (location.hostname !== 'cdn-uploads.mealime.com') {
      console.error('Open a cdn-uploads.mealime.com image in this tab first; the fetches must be same origin.');
      return null;
    }
    const files = [];
    const failed = [];
    let cursor = 0;
    const worker = async () => {
      for (;;) {
        const i = cursor++;
        if (i >= paths.length) return;
        const p = paths[i];
        try {
          const r = await fetch('/uploads/' + p);
          if (!r.ok) failed.push({ p, status: r.status });
          else files.push({ name: p, data: new Uint8Array(await r.arrayBuffer()) });
        } catch (error) {
          failed.push({ p, error: String(error.message ?? error) });
        }
        if ((files.length + failed.length) % 50 === 0) console.log(`  ${files.length + failed.length} of ${paths.length}`);
        await sleep(delayMs);
      }
    };
    await Promise.all(Array.from({ length: concurrency }, worker));
    const zip = storedZip(files);

    // A download from an image or XML document needs a real click, so offer a
    // button rather than clicking programmatically.
    document.querySelectorAll('#miseDl').forEach((e) => e.remove());
    const a = document.createElementNS('http://www.w3.org/1999/xhtml', 'a');
    a.id = 'miseDl';
    a.setAttribute('href', URL.createObjectURL(zip));
    a.setAttribute('download', 'mealime-images.zip');
    a.textContent = `DOWNLOAD ${files.length} MEALIME IMAGES`;
    a.setAttribute('style', 'position:fixed;top:20px;left:20px;z-index:99999;background:#7ac142;color:#fff;font:bold 24px sans-serif;padding:20px 30px;border-radius:8px;text-decoration:none');
    document.documentElement.appendChild(a);
    console.log(`%cPacked ${files.length} images (${(zip.size / 1048576).toFixed(1)} MB), ${failed.length} failed. Click the green button to save mealime-images.zip.`, 'color: green; font-weight: bold');
    if (failed.length) console.warn('Failed:', failed);
    return { fetched: files.length, failed };
  }

  window.__miseImages = { rescue };
  console.log('Run __miseImages.rescue(<paths array from `node src/cli.mjs image-paths`>).');
})();
