import { readFileSync } from 'node:fs';

const dockerfile = readFileSync('Dockerfile.alpine', 'utf8');
const bases = dockerfile.match(/^FROM .+$/gm) ?? [];
if (!bases.length || bases.some(line => !/@sha256:[a-f0-9]{64}$/.test(line))) {
  throw Error('Every runtime base must be pinned by digest');
}
if (/\bapk\s+add\b/.test(dockerfile)
  || !/ca-certificates-bundle-\d{8}-r\d+/.test(dockerfile)) {
  throw Error('Use an explicitly versioned certificate bundle from the pinned base; no live APK resolution');
}
const pins = readFileSync('tools/Dockerfile.pins', 'utf8');
for (const image of ['rust', 'node', 'musl', 'actionlint']) {
  if (!new RegExp(`^FROM .+@sha256:[a-f0-9]{64} AS ${image}$`, 'm').test(pins)) {
    throw Error(`${image} toolchain must be pinned by digest`);
  }
}
console.log('image-inputs: runtime and toolchain digests pinned; certificate version explicit');
