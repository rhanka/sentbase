import assert from 'node:assert/strict';
import { test, after } from 'node:test';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, existsSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { execFileSync, spawnSync } from 'node:child_process';

const cwd = mkdtempSync(join(tmpdir(), 'workflow-test-'));
after(() => rmSync(cwd, { recursive: true, force: true }));
const env = { ...process.env, HOME: cwd, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null',
  GIT_AUTHOR_NAME: 'Human Author', GIT_AUTHOR_EMAIL: 'author@example.org',
  GIT_COMMITTER_NAME: 'Human Committer', GIT_COMMITTER_EMAIL: 'committer@example.org' };
for (const key of ['GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'MAKEFLAGS', 'MFLAGS', 'MAKEOVERRIDES']) delete env[key];
const git = (...args) => execFileSync('git', args, { cwd, env, encoding: 'utf8' }).trimEnd();
mkdirSync(join(cwd, 'tools'));
mkdirSync(join(cwd, '.githooks'));
for (const path of ['Makefile', 'tools/commit.sh', 'tools/check-attribution.sh', '.githooks/commit-msg']) {
  copyFileSync(resolve(path), join(cwd, path));
}
git('init', '-q');
git('config', 'core.hooksPath', '.githooks');
// Keep the copied hook executable, like the tracked hook.
execFileSync('chmod', ['+x', join(cwd, '.githooks/commit-msg')]);
git('config', 'commit.gpgsign', 'true');
function commit(message) {
  writeFileSync(join(cwd, 'fixture'), message);
  git('add', 'fixture');
  return spawnSync('make', ['--no-print-directory', 'commit', `MSG=${message}`], { cwd, env, encoding: 'utf8' });
}

test('should preserve quotes dollars backticks and backslashes without evaluating them', () => {
  for (const message of ['fix: handle "schema".\'table\'', 'fix: preserve $var and $(touch injected)',
    'fix: preserve `touch injected`', 'fix: preserve \\n \\t \\0 C:\\path',
    'fix: preserve $(shell touch injected)']) {
    const result = commit(message);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(git('log', '-1', '--format=%B'), message);
    assert.equal(existsSync(join(cwd, 'injected')), false);
  }
});

test('should reject multiline carriage-return and attributed messages', () => {
  const before = git('rev-parse', 'HEAD');
  for (const message of ['fix: line one\nline two', 'fix: carriage\rreturn', 'Generated with ChatGPT', '']) {
    assert.notEqual(commit(message).status, 0);
    assert.equal(git('rev-parse', 'HEAD'), before);
  }
});

test('should inspect staged unstaged untracked and committed scope and fail without harness', () => {
  const dir = join(cwd, 'scope');
  mkdirSync(dir);
  const g = (...args) => execFileSync('git', args, { cwd: dir, env, encoding: 'utf8' });
  g('init', '-q', '-b', 'main');
  const plan = '# Scope\n## Boundaries\n- **Allowed Paths**:\n  - `BRANCH.md`\n  - `harness.profile.json`\n  - `seed`\n- **Forbidden Paths**:\n  - `Cargo.lock`\n';
  writeFileSync(join(dir, 'BRANCH.md'), plan);
  copyFileSync(resolve('harness.profile.json'), join(dir, 'harness.profile.json'));
  writeFileSync(join(dir, 'seed'), 'baseline');
  g('add', 'BRANCH.md', 'harness.profile.json', 'seed');
  g('-c', 'commit.gpgsign=false', 'commit', '-qm', 'test: baseline');
  g('switch', '-qc', 'scope-test');
  const scope = (extra = {}) => spawnSync('node', [resolve('tools/scope-check.mjs')], {
    cwd: dir, env: { ...env, HARNESS_MODULE: resolve('tmp/toolchain/harness/node_modules/@sentropic/harness/dist/index.js'),
      SCOPE_RANGE: 'main...HEAD', ...extra }, encoding: 'utf8',
  });
  assert.equal(scope().status, 0);
  assert.notEqual(scope({ HARNESS_MODULE: '/nonexistent/harness.js' }).status, 0);
  assert.notEqual(scope({ SCOPE_RANGE: 'invalid...HEAD' }).status, 0);
  writeFileSync(join(dir, 'outside.txt'), 'untracked');
  assert.notEqual(scope().status, 0);
  g('add', 'outside.txt');
  assert.notEqual(scope().status, 0);
  g('-c', 'commit.gpgsign=false', 'commit', '-qm', 'test: committed outside scope');
  assert.notEqual(scope().status, 0); // clean worktree still checks the branch range
  writeFileSync(join(dir, 'BRANCH.md'), plan.replace('  - `seed`', '  - `seed`\n  - `outside.txt`'));
  assert.equal(scope().status, 0);
  writeFileSync(join(dir, 'seed'), 'unstaged');
  writeFileSync(join(dir, 'BRANCH.md'), plan.replace('  - `seed`\n', '  - `outside.txt`\n'));
  assert.notEqual(scope().status, 0);
});

test('should refuse detached pushes before invoking git push', () => {
  const fake = join(cwd, 'fake-git');
  writeFileSync(fake, '#!/bin/sh\ncase "$1" in branch) exit 0;; *) echo unexpected >&2; exit 99;; esac\n', { mode: 0o755 });
  const result = spawnSync('make', ['push', `GIT=${fake}`], { cwd, env, encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stdout, /Refusing detached HEAD or main/);
  assert.doesNotMatch(result.stderr, /unexpected/);
});
