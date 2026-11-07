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
