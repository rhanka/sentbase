import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createReceipt, verifyReceipt } from './image-receipt.mjs';

const sha = 'a'.repeat(40);
const imageId = `sha256:${'b'.repeat(64)}`;
const imageDigest = `sha256:${'c'.repeat(64)}`;
const context = { repo: 'example/sentbase', sha, sourceSha: sha, workflow: 'CI', runId: '123', attempt: '1' };
const metadata = { 'containerimage.digest': imageDigest, 'containerimage.config.digest': imageId };
const jobs = ['attribution', 'no-python', 'lint', 'test', 'ts'];
const checks = () => Object.fromEntries(jobs.map(job => [job, { result: 'success', outputs: { sha } }]));
const receipt = () => createReceipt(context, checks(), metadata, imageId);

test('should bind a receipt to the built image and successful jobs for one SHA', () => {
  const result = receipt();
  assert.equal(result.imageDigest, imageDigest);
  assert.deepEqual(result.testedJobs, jobs.map(job => ({ job, sha })));
  assert.deepEqual(verifyReceipt(JSON.parse(JSON.stringify(result)), receipt()), result);
});

test('should accept the manifest image ID returned by Docker containerd stores', () => {
  const result = createReceipt(context, checks(), { 'containerimage.digest': imageDigest }, imageDigest);
  assert.equal(result.imageId, imageDigest);
});

test('should reject missing, failed, skipped, cancelled and stale checks', () => {
  for (const job of jobs) {
    for (const result of ['failure', 'skipped', 'cancelled', undefined]) {
      const needs = checks();
      needs[job] = { result, outputs: { sha } };
      assert.throws(() => createReceipt(context, needs, metadata, imageId), /Required job/);
    }
    const needs = checks();
    delete needs[job];
    assert.throws(() => createReceipt(context, needs, metadata, imageId), /Required job/);
    needs[job] = { result: 'success', outputs: { sha: 'd'.repeat(40) } };
    assert.throws(() => createReceipt(context, needs, metadata, imageId), /Required job/);
  }
});

test('should reject missing identity, checkout mismatch and image substitution', () => {
  for (const key of Object.keys(context)) {
    assert.throws(() => createReceipt({ ...context, [key]: '' }, checks(), metadata, imageId), /identity/);
  }
  assert.throws(() => createReceipt({ ...context, sourceSha: 'd'.repeat(40) }, checks(), metadata, imageId), /identity/);
  assert.throws(() => createReceipt(context, checks(), {}, imageId), /digest/);
  assert.throws(() => createReceipt(context, checks(), metadata, `sha256:${'d'.repeat(64)}`), /digest/);
});

test('should reject receipt reuse across runs, attempts, source commits and images', () => {
  for (const key of ['repo', 'sourceSha', 'workflow', 'runId', 'attempt', 'imageDigest', 'imageId', 'testedJobs']) {
    assert.throws(() => verifyReceipt({ ...receipt(), [key]: 'stale' }, receipt()), /does not match/);
  }
});
