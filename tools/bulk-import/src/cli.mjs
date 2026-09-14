#!/usr/bin/env node
// Inventories a browser bookmarks export, ahead of the bulk URL import.

import { parseArgs } from 'node:util';
import path from 'node:path';

import { runInventory } from './inventory.mjs';

const USAGE = `
bulk-import, inventory a browser bookmarks export.

Usage:
  node src/cli.mjs inventory [--in <bookmarks.html>] [--folder <name>]

Options:
  --in <file>      Bookmarks export. Default ../../data/bookmarks.html
  --out <file>     Default ../../data/bookmarks_inventory.json
  --nyt <file>     NYT Recipe Box export, to mark URLs already saved there.
                   Default ../../data/nyt/nyt_recipe_box.json
  --folder <name>  Only bookmarks whose folder path contains this text.
  --help
`;

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      in: { type: 'string' },
      out: { type: 'string' },
      nyt: { type: 'string' },
      folder: { type: 'string' },
      help: { type: 'boolean', default: false },
    },
  });

  if (values.help || positionals[0] !== 'inventory') {
    console.log(USAGE);
    process.exit(values.help ? 0 : 2);
  }

  const dataDir = path.join(import.meta.dirname, '..', '..', '..', 'data');
  await runInventory({
    inFile: path.resolve(values.in ?? path.join(dataDir, 'bookmarks.html')),
    outFile: path.resolve(values.out ?? path.join(dataDir, 'bookmarks_inventory.json')),
    nytFile: path.resolve(values.nyt ?? path.join(dataDir, 'nyt', 'nyt_recipe_box.json')),
    folder: values.folder ?? null,
  });
}

main().catch((error) => {
  console.error(`\nFailed: ${error.message}`);
  process.exit(1);
});
