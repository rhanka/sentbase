# Fix: clear npm audit, bump @hono/node-server and hono past path-handling advisories

## Objective
Replace the vulnerable `@hono/node-server` 2.0.2 with 2.1.6 and `hono` 4.12.25 with 4.13.17, clear every
`npm audit` finding of the locked graph (dev toolchain included), keep a single runtime copy of each, and add a
regression test that fails on 2.0.2 and passes on 2.1.6.

## Scope / Guardrails
- Stacked on `chore/harness-adopt` (PR #1): the CI and make toolchain this branch relies on land there first.
- Only the Node dependency graph, one regression test and two npm make targets change. No engine change.
- Make-only; worktree `tmp/fix-hono-node-server-ghsa`. Zero Python. English.
- Request origin: s-conductor security notice, 2026-11-07 (references: sentropic PR #938, immo PR #1016).

## Branch Scope Boundaries (MANDATORY)
- **Allowed Paths (implementation scope)**:
  - `BRANCH.md`
  - `package.json`
  - `package-lock.json`
  - `tests/security/**`
- **Forbidden Paths (must not change in this branch)**:
  - `crates/**`
  - `Cargo.toml`
  - `Cargo.lock`
  - `.github/workflows/**`
- **Conditional Paths (allowed only with explicit exception when not already listed in Allowed Paths)**:
  - `Makefile` (BR02-EX1)
- **Exception process**:
  - Declare exception ID `BRxx-EXn` in `## Feedback Loop` before touching any conditional/forbidden path.

## Feedback Loop
- `BR02-EX1` Makefile: add `npm-install` (NPM_LIB, NPM_DEV, pinned toolchain, `--save-exact`) and `npm-audit`
  (`--audit-level=high`) so dependency bumps and their audit go through make. Impact: two new targets. Rollback: revert.
- Advisory register for `@hono/node-server` 2.0.2, all fixed by 2.1.6:
  - Repository advisories (honojs/node-server, published 2026-11-02, not yet in the global database: read with
    `gh api /repos/honojs/node-server/security-advisories`; `/advisories/<id>` returns 404):
    GHSA-jpvv-r467-5p4w (backslash parsed as a path separator, bypassing path-based access control at a reverse
    proxy; >= 2.0.0 < 2.1.6, < 1.19.18), GHSA-7v5p-43qr-wch5 (WebSocket upgrade request-target starting with `//`
    replaces the host in `c.req.url`, bypassing `Origin` checks; >= 2.0.0 < 2.1.6), GHSA-qv5m-9pm6-hqp3 (unhandled
    `ECONNRESET` during an async WebSocket upgrade crashes the process; >= 2.0.0 < 2.1.6).
  - Global advisories (`gh api '/advisories?affects=@hono/node-server&ecosystem=npm'`): GHSA-rmxm-3fg6-px4f
    (serveStatic second decode, fixed 2.1.3), GHSA-9mqv-5hh9-4cgg (aborted WebSocket handshake memory leak, fixed
    2.0.10), GHSA-frvp-7c67-39w9 (encoded backslash in serve-static on Windows, fixed 2.0.5).
  - The 2.1.6 serve-static diff also rejects any `%` left after routing decode, any backslash in the filename,
    non-GET/HEAD methods, and malformed ranges.
- `attention` Exposure: only `tools/sentropic-poc/http-poc.ts` imports `@hono/node-server` (`serve`, no `serveStatic`,
  no WebSocket); the vulnerable paths were not reachable from shipped code. The bump is preventive.
- Discriminating cases (fail on 2.0.2, pass on 2.1.6): version floor; `%2541` double decode through serveStatic
  (GHSA-rmxm); `/public/..\internal/secret` and `/public\..\internal/secret` reaching a route guarded only at the
  proxy (GHSA-jpvv). Encoded-backslash and app-guarded variants pass on both versions and stay as invariant checks.
  The WebSocket advisories are not exercised: no WebSocket upgrade exists in this repository.
- `attention` Flaky: `tests/parity/sql-smoke.test.ts > opendb-node accepts typed primary-key schema over pgwire`
  timed out once (38.7 s > 30 s) on a cold worktree, then passed on the same commit; unrelated to this branch.

## Plan / Todo (lot-based)
- [x] **Lot 0 — Baseline**
  - [x] Usage audit: only `tools/sentropic-poc/http-poc.ts` imports `@hono/node-server`.
  - [x] Targets exist on npm, all MIT: `@hono/node-server@2.1.6`, `hono@4.13.17`, `vitest@4.1.12`.
- [x] **Lot 1 — Bumps and regression test**
  - [x] `make npm-install NPM_LIB=@hono/node-server@2.1.6`, `NPM_LIB=hono@4.13.17`, `NPM_LIB=vitest@4.1.12 NPM_DEV=1`.
  - [x] Single copies in the lockfile: `@hono/node-server` 2.1.6, `hono` 4.13.17, `vitest` 4.1.12, `vite` 8.3.6.
  - [x] `tests/security/hono-node-server-path.test.ts` (20 cases): fails on 2.0.2 (version floor, `%2541`
        double decode, two backslash proxy-bypass paths), passes on 2.1.6.
  - [x] Lot gate: `make npm-audit` (0 vulnerabilities), `make check-ts`, `make vitest` (58/58).
- [ ] **Lot N — Final validation**
  - [ ] `make check-attribution ATTRIBUTION_RANGE=chore/harness-adopt..HEAD`; CI green; owner sign-off; remove `BRANCH.md` before merge.
