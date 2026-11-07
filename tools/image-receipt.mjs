import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const requiredJobs = ['attribution', 'no-python', 'lint', 'test', 'ts'];
const digest = /^sha256:[a-f0-9]{64}$/;

// Bind the loaded, smoke-tested image to successful checks of the same SHA.
export function createReceipt(context, needs, metadata, imageId) {
  const { repo, sha, sourceSha, workflow, runId, attempt } = context;
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo ?? '') || !/^[a-f0-9]{40}$/.test(sha ?? '')
    || sourceSha !== sha || !workflow?.trim()
    || !/^[1-9]\d*$/.test(runId ?? '') || !/^[1-9]\d*$/.test(attempt ?? '')) {
    throw Error('Missing or inconsistent workflow identity');
  }
  if (!digest.test(metadata['containerimage.digest'] ?? '') || !digest.test(imageId ?? '')
    || metadata['containerimage.config.digest'] !== imageId) {
    throw Error('Invalid digest or loaded image does not match build metadata');
  }
  for (const job of requiredJobs) {
    if (needs[job]?.result !== 'success' || needs[job]?.outputs?.sha !== sha) {
      throw Error(`Required job ${job} did not successfully test ${sha}`);
    }
  }
  return {
    schema: 1, repo, sourceSha, workflow, runId, attempt,
    imageDigest: metadata['containerimage.digest'], imageId,
    testedJobs: requiredJobs.map(job => ({ job, sha })),
  };
}

export function verifyReceipt(receipt, expected) {
  if (JSON.stringify(receipt) !== JSON.stringify(expected)) {
    throw Error('Image receipt does not match this image, SHA, run and attempt');
  }
  return receipt;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [mode, file, metadataFile, imageIdFile] = process.argv.slice(2);
  if (!['write', 'verify'].includes(mode) || !file || !metadataFile || !imageIdFile) {
    throw Error('Usage: image-receipt.mjs write|verify receipt metadata image-id');
  }
  const env = process.env;
  const expected = createReceipt({
    repo: env.GITHUB_REPOSITORY, sha: env.GITHUB_SHA, sourceSha: env.SOURCE_SHA,
    workflow: env.GITHUB_WORKFLOW, runId: env.GITHUB_RUN_ID, attempt: env.GITHUB_RUN_ATTEMPT,
  }, JSON.parse(env.CI_NEEDS ?? '{}'), JSON.parse(readFileSync(metadataFile, 'utf8')),
  readFileSync(imageIdFile, 'utf8').trim());
  if (mode === 'write') writeFileSync(file, `${JSON.stringify(expected, null, 2)}\n`);
  else verifyReceipt(JSON.parse(readFileSync(file, 'utf8')), expected);
  console.log(`Image receipt ${mode}: ${expected.imageDigest}`);
}
