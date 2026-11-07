import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { deepStrictEqual } from 'node:assert';

const requiredJobs = ['attribution', 'no-python', 'lint', 'test', 'ts'];
const digest = /^sha256:[a-f0-9]{64}$/;

// Source checks and exact-image integration are separate evidence.
// This JSON is not an authenticated attestation; consumers must obtain a trusted CI artifact.
export function createReceipt(context, needs, metadata, imageId, integration) {
  const { repo, sha, sourceSha, workflow, runId, attempt } = context;
  if (!/^[\w.-]+\/[\w.-]+$/.test(repo ?? '') || !/^[a-f0-9]{40}$/.test(sha ?? '')
    || sourceSha !== sha || !workflow?.trim()
    || !/^[1-9]\d*$/.test(runId ?? '') || !/^[1-9]\d*$/.test(attempt ?? '')) {
    throw Error('Missing or inconsistent workflow identity');
  }
  if (!digest.test(metadata['containerimage.digest'] ?? '') || !digest.test(imageId ?? '')
    || ![metadata['containerimage.digest'], metadata['containerimage.config.digest']].includes(imageId)) {
    throw Error('Invalid digest or loaded image does not match build metadata');
  }
  for (const job of requiredJobs) {
    if (needs[job]?.result !== 'success' || needs[job]?.outputs?.sha !== sha) {
      throw Error(`Required job ${job} did not successfully test ${sha}`);
    }
  }
  if (integration?.result !== 'success' || integration.sourceSha !== sha
    || integration.imageId !== imageId || integration.imageDigest !== metadata['containerimage.digest']
    || !['sql-write-read', 'restart-recovery'].every(check => integration.checks?.includes(check))) {
    throw Error('Image integration did not successfully exercise this exact source and digest');
  }
  return {
    schema: 2, repo, sourceSha, workflow, runId, attempt,
    imageDigest: metadata['containerimage.digest'], imageId,
    testedJobs: requiredJobs.map(job => ({ job, sha })),
    imageIntegration: { ...integration },
  };
}

export function verifyReceipt(receipt, ...inputs) {
  const expected = createReceipt(...inputs);
  try { deepStrictEqual(receipt, expected); } catch {
    throw Error('Image receipt does not match this image, SHA, run and attempt');
  }
  return receipt;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [mode, file, metadataFile, imageIdValue, integrationFile] = process.argv.slice(2);
  if (!['write', 'verify'].includes(mode) || !file || !metadataFile || !imageIdValue || !integrationFile) {
    throw Error('Usage: image-receipt.mjs write|verify receipt metadata image-id-or-file integration');
  }
  const env = process.env;
  const inputs = [{
    repo: env.GITHUB_REPOSITORY, sha: env.GITHUB_SHA, sourceSha: env.SOURCE_SHA,
    workflow: env.GITHUB_WORKFLOW, runId: env.GITHUB_RUN_ID, attempt: env.GITHUB_RUN_ATTEMPT,
  }, JSON.parse(env.CI_NEEDS ?? '{}'), JSON.parse(readFileSync(metadataFile, 'utf8')),
  digest.test(imageIdValue) ? imageIdValue : readFileSync(imageIdValue, 'utf8').trim(),
  JSON.parse(readFileSync(integrationFile, 'utf8'))];
  const expected = createReceipt(...inputs);
  if (mode === 'write') writeFileSync(file, `${JSON.stringify(expected, null, 2)}\n`);
  else verifyReceipt(JSON.parse(readFileSync(file, 'utf8')), ...inputs);
  console.log(`Image receipt ${mode}: ${expected.imageDigest}`);
}
