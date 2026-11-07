#!/bin/bash
set -euo pipefail
image_id=$(cat tmp/ci/image-id)
test "$(docker image inspect "$image_id" --format '{{.Id}}')" = "$image_id"
toolchain=${TOOLCHAIN_IMAGE:?}
name="sentbase-image-gate-$$"
root=$PWD
rm -f tmp/ci/image-integration.json
cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then docker logs "$name" >&2 || true; fi
  docker rm -f "$name" >/dev/null 2>&1 || true
  docker volume rm "$name" >/dev/null 2>&1 || true
  docker network rm "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker network create "$name" >/dev/null
docker volume create "$name" >/dev/null
docker run -d --name "$name" --network "$name" --network-alias database \
  -v "$name:/var/lib/opendb" "$image_id" --node-id 1 >/dev/null
test "$(docker inspect "$name" --format '{{.Config.User}}')" = opendb
wait_health() {
  for attempt in {1..30}; do
    if docker exec "$name" wget -q -O /dev/null http://127.0.0.1:8080/healthz; then return; fi
    sleep 1
  done
  echo 'Image health did not become ready' >&2
  return 1
}
probe() {
  docker run --rm -i --network "$name" -v "$root:/workspace:ro" -w /workspace \
    "$toolchain" node --input-type=module - "$1" <<'JS'
import assert from 'node:assert/strict';
import pg from 'pg';
const client = new pg.Client({ host: 'database', port: 5432, user: 'opendb', database: 'opendb' });
await client.connect();
try {
  if (process.argv[2] === 'write') {
    await client.query('CREATE TABLE image_gate (id INTEGER PRIMARY KEY, payload TEXT)');
    await client.query("INSERT INTO image_gate (id, payload) VALUES (1, 'persisted')");
  }
  const { rows } = await client.query('SELECT payload FROM image_gate WHERE id = 1');
  assert.deepEqual(rows, [{ payload: 'persisted' }]);
} finally { await client.end(); }
JS
}
wait_health
probe write
docker restart --time 5 "$name" >/dev/null
wait_health
probe recover
test "$(docker inspect "$name" --format '{{.Image}}')" = "$image_id"
docker run --rm -i --user "$(id -u):$(id -g)" -v "$root:/workspace" -w /workspace \
  -e IMAGE_ID="$image_id" -e SOURCE_SHA "${toolchain}" node --input-type=module - <<'JS'
import { readFileSync, writeFileSync } from 'node:fs';
const metadata = JSON.parse(readFileSync('tmp/ci/image-metadata.json', 'utf8'));
const imageDigest = metadata['containerimage.digest'];
if (!/^sha256:[a-f0-9]{64}$/.test(imageDigest)) throw Error('Invalid build digest');
writeFileSync('tmp/ci/image-integration.json', JSON.stringify({ result: 'success',
  sourceSha: process.env.SOURCE_SHA, imageDigest, imageId: process.env.IMAGE_ID,
  checks: ['sql-write-read', 'restart-recovery'] }, null, 2) + '\n');
console.log(`image-integration: OK (sql-write-read, restart-recovery); exercised ${imageDigest}; ${process.env.IMAGE_ID}`);
JS
