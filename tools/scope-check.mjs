import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

// Tooling is installed at an exact version by Make, separately from product dependencies.
const harnessPath = process.env.HARNESS_MODULE ??
  'tmp/toolchain/harness/node_modules/@sentropic/harness/dist/index.js';
const { parseBranchMd, checkScope } = await import(pathToFileURL(resolve(harnessPath)).href);
const git = (...args) => execFileSync('git', args, { encoding: 'utf8' });
const branch = git('branch', '--show-current').trim();
if (!branch && !process.env.CI) throw Error('Detached HEAD is only supported in CI');
const range = process.env.SCOPE_RANGE ?? 'main...HEAD';
const files = [...new Set([
  git('diff', '--name-only', '-z', range, '--'),
  git('diff', '--cached', '--name-only', '-z', '--'),
  git('diff', '--name-only', '-z', '--'),
  git('ls-files', '--others', '--exclude-standard', '-z'),
].flatMap(output => output.split('\0').filter(Boolean)))];
const text = readFileSync('BRANCH.md', 'utf8');
const parsed = parseBranchMd(text);
if (!parsed.allowedPaths.length || !parsed.forbiddenPaths.length) throw Error('Incomplete BRANCH.md scope');
const profile = JSON.parse(readFileSync('harness.profile.json', 'utf8'));
profile.exceptionIdPattern = new RegExp(profile.exceptionIdPattern);
// The harness API accepts the project profile directly; no built-in-profile substitution.
const result = checkScope({
  stagedFiles: files, profile,
  boundary: { allowed: parsed.allowedPaths, forbidden: parsed.forbiddenPaths, conditional: parsed.conditionalPaths },
  declaredExceptions: parsed.exceptions,
});
for (const violation of result.violations) console.error(`${violation.code}: ${violation.message}`);
if (!result.pass) process.exit(1);
console.log(`scope-check: OK (${files.length} paths; ${range} plus staged, unstaged and untracked)`);
