#!/usr/bin/env node
// Check that this linter's descriptor list still matches the app's.
//
// The list exists twice on purpose: the linter validates the fixtures without
// a Swift toolchain, and the cloud environment has none. Duplication that
// nothing checks is how two implementations quietly disagree, so this checks.

import { readFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(here, '..', '..', '..');

const swift = await readFile(resolve(repoRoot, 'Mise/Domain/Services/CanonicalMatcher.swift'), 'utf8');
const block = swift.split('static let descriptors: Set<String> = [')[1]?.split('\n    ]')[0] ?? '';
// Comment lines quote example phrases, which are not descriptor words.
const code = block.split('\n').filter((line) => !line.trim().startsWith('//')).join('\n');
const fromSwift = new Set([...code.matchAll(/"([^"]+)"/g)].map((m) => m[1]));

const { DESCRIPTORS } = await import('./matching.mjs');
const fromJS = DESCRIPTORS ?? new Set();

const missing = [...fromSwift].filter((w) => !fromJS.has(w)).sort();
const extra = [...fromJS].filter((w) => !fromSwift.has(w)).sort();

if (missing.length === 0 && extra.length === 0) {
  console.log(`descriptors in step: ${fromSwift.size} words`);
  process.exit(0);
}
if (missing.length) console.error(`in CanonicalMatcher.swift but not here: ${missing.join(', ')}`);
if (extra.length) console.error(`here but not in CanonicalMatcher.swift: ${extra.join(', ')}`);
process.exit(1);
