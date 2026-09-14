#!/usr/bin/env node
// Command line entry point for the NYT Cooking Recipe Box export.
//
// The collecting happens in the browser, see browser/collect.js. This turns the
// downloaded dump into data/nyt/nyt_recipe_box.json.

import { parseArgs } from 'node:util';
import path from 'node:path';

import { runConvert } from './convert.mjs';

const USAGE = `
nyt-export, a one time read only export of your NYT Cooking Recipe Box.

Collecting happens in the browser. Paste browser/collect.js into the console on
cooking.nytimes.com while signed in, then follow the steps it prints.

Usage:
  node src/cli.mjs convert --in <dump.json> [--out <file>]

Options:
  --in <file>    The nyt-recipe-box-raw.json downloaded by the browser script.
  --out <file>   Default ../../data/nyt/nyt_recipe_box.json
  --help
`;

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: { in: { type: 'string' }, out: { type: 'string' }, help: { type: 'boolean', default: false } },
  });

  if (values.help || positionals[0] !== 'convert' || !values.in) {
    console.log(USAGE);
    process.exit(values.help ? 0 : 2);
  }

  const outFile = path.resolve(
    values.out ?? path.join(import.meta.dirname, '..', '..', '..', 'data', 'nyt', 'nyt_recipe_box.json')
  );
  await runConvert({ inFile: path.resolve(values.in), outFile });
}

main().catch((error) => {
  console.error(`\nFailed: ${error.message}`);
  process.exit(1);
});
