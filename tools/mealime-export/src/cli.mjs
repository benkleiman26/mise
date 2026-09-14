#!/usr/bin/env node
// Command line entry point for the Mealime rescue.
//
//   npm run discover    work out which endpoints and auth scheme answer
//   npm run export      pull everything down, raw
//   npm run normalize   reshape the raw files for the app importer
//
// The token is read from MEALIME_AUTH_TOKEN and is never written to disk or to
// the repository. See README.md for how to copy it out of the browser.

import { parseArgs } from 'node:util';
import path from 'node:path';

import { ReadOnlyClient } from './http.mjs';
import { DEFAULT_BASE, probeCollections, resolveAuthScheme } from './discover.mjs';
import { runExport } from './export.mjs';
import { runImages } from './images.mjs';
import { runNormalize } from './normalize.mjs';

const USAGE = `
mealime-export, a one time read only export of a Mealime account.

Usage:
  MEALIME_AUTH_TOKEN=... node src/cli.mjs <command> [options]

Commands:
  discover    Probe the API and report which endpoints answer. Safe to run first.
  export      Fetch everything and write it raw to <out>/raw.
  normalize   Reshape <out>/raw into the format the app importer reads. Offline.
  images      Download the recipe images referenced by the export. Do this
              before the shutdown: the image URLs die with the service.

Options:
  --out <dir>      Output directory. Default ../../data/mealime
  --base <url>     API base. Default ${DEFAULT_BASE}
  --scheme <name>  Skip auth detection: bearer, token, x-auth-token, x-user-token, query
  --limit <n>      Stop after n recipe detail fetches. Use for a smoke test.
  --concurrency <n>  Parallel image downloads. Default 4.
  --force          Re-fetch recipes already saved. Default is to resume.
  --include-mealime-content
                   Keep the full text of Mealime's own recipes in
                   mealime-export.json. Only for your own private copy. The
                   default keeps a reference (id, name, image) for those and
                   full content only for recipes you imported yourself.
  --help

This tool only ever issues GET requests, and only to mealime.com hosts. It cannot
modify or delete anything in the account.
`;

function requireToken() {
  const token = process.env.MEALIME_AUTH_TOKEN;
  if (!token) {
    console.error('MEALIME_AUTH_TOKEN is not set. See README.md, section "Getting your token".');
    process.exit(2);
  }
  return token;
}

async function main() {
  const { values, positionals } = parseArgs({
    allowPositionals: true,
    options: {
      out: { type: 'string' },
      base: { type: 'string', default: DEFAULT_BASE },
      scheme: { type: 'string' },
      limit: { type: 'string' },
      concurrency: { type: 'string' },
      force: { type: 'boolean', default: false },
      'include-mealime-content': { type: 'boolean', default: false },
      help: { type: 'boolean', default: false },
    },
  });

  const command = positionals[0];
  if (values.help || !command) {
    console.log(USAGE);
    process.exit(values.help ? 0 : 2);
  }

  const outDir = path.resolve(
    values.out ?? path.join(import.meta.dirname, '..', '..', '..', 'data', 'mealime')
  );
  const limit = values.limit ? Number(values.limit) : Infinity;

  switch (command) {
    case 'discover': {
      const token = requireToken();
      console.log('Trying auth schemes');
      const resolved = await resolveAuthScheme({ token, base: values.base, log: console.log });
      if (!resolved) {
        console.error('\nNothing authenticated. The token is probably stale, copy a fresh one.');
        console.error('If it still fails, use the browser fallback in browser/.');
        process.exit(1);
      }
      console.log(`\nAuth scheme: ${resolved.scheme} (via ${resolved.identityPath})\n`);
      const client = new ReadOnlyClient({ token, scheme: resolved.scheme });
      console.log('Probing collections');
      await probeCollections({ client, base: values.base, log: console.log });
      console.log('\nIf the counts look right, run: npm run export');
      break;
    }
    case 'export': {
      const token = requireToken();
      console.log(`Writing to ${outDir}\n`);
      await runExport({ token, outDir, base: values.base, scheme: values.scheme, force: values.force, limit });
      console.log('\nNext: npm run normalize');
      break;
    }
    case 'images': {
      console.log(`Reading ${outDir}\n`);
      await runImages({
        outDir,
        concurrency: values.concurrency ? Number(values.concurrency) : 4,
        force: values.force,
      });
      break;
    }
    case 'normalize': {
      console.log(`Reading ${outDir}\n`);
      await runNormalize({ outDir, includeMealimeContent: values['include-mealime-content'] });
      break;
    }
    default:
      console.error(`Unknown command: ${command}`);
      console.log(USAGE);
      process.exit(2);
  }
}

main().catch((error) => {
  console.error(`\nFailed: ${error.message}`);
  process.exit(1);
});
