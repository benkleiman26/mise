#!/usr/bin/env node
// Two commands.
//
//   node src/cli.mjs urls      prints the line to paste into the browser
//   node src/cli.mjs convert   turns what the browser downloaded into an
//                              import file for the app
//
// Reads only. The Recipe Box export in data/nyt/ is never modified.

import { readdir, readFile, mkdir, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { convertLibrary } from './convert.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..', '..');
const nytDir = resolve(join(repoRoot, 'data', 'nyt'));

function option(name, fallback) {
  const index = process.argv.indexOf(name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

/** Every recipe url in the Recipe Box export, with its folders and cooked flag. */
function harvest(node, found = new Map()) {
  if (!node || typeof node !== 'object') return found;
  if (Array.isArray(node)) {
    node.forEach((child) => harvest(child, found));
    return found;
  }

  const url = typeof node.url === 'string' ? node.url
    : typeof node.href === 'string' ? node.href
    : null;

  if (url && /cooking\.nytimes\.com\/recipes\//.test(url)) {
    const clean = url.split('?')[0];
    const existing = found.get(clean) ?? { url: clean, folders: [], cooked: false };
    for (const folder of [].concat(node.folders ?? node.folder ?? node.lists ?? [])) {
      const name = typeof folder === 'string' ? folder : String(folder?.name ?? '').trim();
      if (name && !existing.folders.includes(name)) existing.folders.push(name);
    }
    if (node.cooked === true || node.isCooked === true) existing.cooked = true;
    found.set(clean, existing);
  }

  for (const value of Object.values(node)) harvest(value, found);
  return found;
}

async function readJSONIn(directory) {
  const names = (await readdir(directory)).filter((n) => n.endsWith('.json')).sort();
  const docs = [];
  for (const name of names) {
    try {
      docs.push({ name, data: JSON.parse(await readFile(join(directory, name), 'utf8')) });
    } catch (error) {
      console.error(`  could not read ${name}: ${error.message}`);
    }
  }
  return docs;
}

const command = process.argv[2];

if (command === 'urls') {
  const docs = await readJSONIn(nytDir).catch((error) => {
    console.error(`Could not read ${nytDir}\n  ${error.message}`);
    process.exit(1);
  });

  const found = new Map();
  for (const doc of docs) harvest(doc.data, found);
  const entries = [...found.values()];

  if (entries.length === 0) {
    console.error(`No NYT recipe urls found in ${nytDir}.`);
    console.error('Expected the Recipe Box export from tools/nyt-export to be there.');
    process.exit(1);
  }

  console.error(`${entries.length} recipes found in ${nytDir}. Paste the line below into the browser console.\n`);
  // To stdout, so it can be piped to pbcopy.
  console.log(`__nyt.fetchAll(${JSON.stringify(entries)})`);
  process.exit(0);
}

if (command === 'convert') {
  const inFile = resolve(option('--in', join(process.env.HOME ?? '~', 'Downloads', 'nyt-recipes.json')));
  const outFile = resolve(option('--out', join(repoRoot, 'data', 'mise', 'nyt_import.json')));

  let fetched;
  try {
    fetched = JSON.parse(await readFile(inFile, 'utf8'));
  } catch (error) {
    console.error(`Could not read ${inFile}\n  ${error.message}`);
    console.error('\nThat is the file __nyt.rescue() downloaded. Pass --in <path> if it is elsewhere.');
    process.exit(1);
  }

  const entries = Array.isArray(fetched?.recipes) ? fetched.recipes : [];
  const { document, report } = convertLibrary(entries);

  await mkdir(dirname(outFile), { recursive: true });
  await writeFile(outFile, `${JSON.stringify(document, null, 2)}\n`, 'utf8');

  console.log(`Read ${report.read} fetched recipes from ${inFile}`);
  console.log(`Converted ${report.converted}, ${report.ingredientLines} ingredient lines`);
  if (report.cooked) console.log(`  ${report.cooked} are marked cooked`);
  if (report.withoutTime) console.log(`  ${report.withoutTime} have no time recorded`);
  if (report.withoutSteps) console.log(`  ${report.withoutSteps} have no steps`);
  for (const { where, why } of report.skipped) console.log(`  skipped ${where}: ${why}`);
  if (Array.isArray(fetched.failures) && fetched.failures.length) {
    console.log(`\n${fetched.failures.length} pages failed in the browser. __nyt.retryFailures() retries just those.`);
  }

  console.log(`\nWrote ${outFile}`);
  console.log('That file stays on this machine. It is inside data/, which git ignores.');
  process.exit(0);
}

console.error('Usage:\n  node src/cli.mjs urls\n  node src/cli.mjs convert [--in <fetched.json>] [--out <import.json>]');
process.exit(1);
