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
const makefile = readFileSync('Makefile', 'utf8');
for (const image of ['RUST', 'NODE', 'MUSL', 'ACTIONLINT']) {
  if (!new RegExp(`^${image}_IMAGE := .+@sha256:[a-f0-9]{64}$`, 'm').test(makefile)) {
    throw Error(`${image} toolchain must be pinned by digest`);
  }
}
console.log('image-inputs: runtime and toolchain digests pinned; certificate version explicit');
