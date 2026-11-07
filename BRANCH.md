# Chore: adopt the sentropic harness in sentbase (opendb import)

## Objective
Bring sentbase (which absorbs the opendb repository and history) under the sentropic harness (rules, scope control, make-only, commit discipline, Track, CI) and make
AI/agent attribution in commits mechanically impossible, after the owner-approved history purge.

## Scope / Guardrails
- Scope limited to governance files, the attribution guard, Makefile workflow targets and CI bootstrap.
- No engine behaviour change: `crates/**` only for lint-only fixes under BR01-EX5. Make-only; worktree `tmp/chore-harness-adopt`.
- Built on rewritten `main` (`b1a8f1f`); six historical commits were re-authored with identical trees.
- Zero Python. All new text in English.

## Branch Scope Boundaries (MANDATORY)
- **Allowed Paths (implementation scope)**:
  - `AGENTS.md`
  - `CLAUDE.md`
  - `BRANCH.md`
  - `harness.profile.json`
  - `rules/**`
  - `plan/**`
  - `tools/check-attribution.sh`
  - `tools/check-attribution.test.mjs`
  - `tools/scope-check.mjs`
  - `tools/workflow.test.mjs`
  - `tools/commit.sh`
  - `tools/image-integration.sh`
  - `tools/check-image-inputs.mjs`
  - `tools/no-python.ts`
  - `tools/image-receipt.mjs`
  - `tools/image-receipt.test.mjs`
  - `.github/dependabot.yml`
  - `.github/CODEOWNERS`
  - `.githooks/**`
  - `.claude/settings.json`
  - `README.md`
- **Forbidden Paths (must not change in this branch)**:
  - `Cargo.lock`
  - `package-lock.json`
- **Conditional Paths (allowed only with explicit exception when not already listed in Allowed Paths)**:
  - `Makefile` (BR01-EX1)
  - `LICENSE` (BR01-EX2)
  - `.github/workflows/**` (BR01-EX3)
  - `.track/**` (BR01-EX4)
  - `crates/**/*.rs` (BR01-EX5, lint-only)
  - `Cargo.toml` (BR01-EX6, license metadata only)
  - `package.json` (BR01-EX6, license metadata only)
  - `Dockerfile.alpine` (BR01-EX6, pinned runtime inputs)
- **Exception process**:
  - Declare exception ID `BRxx-EXn` in `## Feedback Loop` before touching any conditional/forbidden path.

## Feedback Loop
- `BR01-EX1` Makefile: replace hardcoded worktree path by `$(CURDIR)`; replace `commit`/`ship` (which ran
  `git add -A` and pushed to main) by hook-enforced `commit`, branch-only `push`, `hooks`, `check-attribution`,
  `scope-check`; run quality targets in digest-pinned Rust/Node images with worktree-local caches,
  and build the musl binary/image plus verify its receipt through Make. Impact: workflow targets only.
  Rollback: revert the commit.
- `BR01-EX2` LICENSE: add MIT (owner direction 2026-11-06: full MIT). The repository lacked a LICENSE file;
  Cargo metadata previously declared Apache-2.0. Rollback: none intended for published license grants.
- `BR01-EX3` CI: add a first GitHub Actions workflow (attribution guard, no-python, lint, tests, TS,
  image receipt) and weekly Dependabot updates. Impact: validation only, no publication. Rollback: revert.
- `BR01-EX4` Track: `track init` for opendb realization state. Rollback: revert.
- `BR01-EX5` Engine lint debt: `make clippy` (-D warnings) fails on `main` (~22 errors in wal.rs, raft.rs,
  recovery.rs, executor.rs, parser.rs). Fix them without behaviour change so CI can be green. Impact: engine
  source, lint-only; all Rust tests must still pass. Rollback: revert the commits.
- `BR01-EX6` Owner-requested review fixes: align Cargo/npm license metadata with MIT and pin the Alpine
  runtime inputs. No dependency or lockfile change, no engine behaviour change. Rollback: revert.
- `attention` SQL parser: `parse_column_type_tokens` consumes only `CHARACTER`, so
  `CREATE TABLE t (label CHARACTER VARYING)` fails with `unsupported column constraint on label`.
  The shadowed two-token arm was unreachable and has been removed without changing this behaviour.
  Owner: SQL maintainer; bounded fix: recognize and consume `CHARACTER VARYING` before the generic text
  arm; acceptance: that CREATE TABLE succeeds with a Text column and bare CHARACTER still works;
  verification: focused parser tests plus `make test-sql ENV=test-harness-adopt`.
- Lot 2 outcome (BR01-EX5): engine Clippy debt is resolved without behaviour changes.
  `make clippy ENV=test-harness-adopt` passes with `--workspace --all-targets --locked -- -D warnings`.
  `make test ENV=test-harness-adopt`, `make fmt-check ENV=test-harness-adopt` and
  `make -k check ENV=test-harness-adopt` all exit 0 (330 Rust, 38 Vitest, 5 image-receipt tests).
  Rust previously counted 331 tests because `debug_comments_table` had duplicate `#[test]` attributes.
  Raft helpers box their large errors; no `allow(clippy::result_large_err)` is used.
  The only new allow is `clippy::double_must_use` on `RecoveryStatusFetcher::fetch`, because
  async_trait generates a redundant `#[must_use]` attribute on its already-must-use future.
- Toolchain licenses: official Node (MIT), Rust (MIT OR Apache-2.0), actionlint (MIT); no new package dependency.
- Image validation: `make image ENV=test-harness-adopt` builds `Dockerfile.alpine` and runs its immutable
  image ID with `--help`. Receipt CLI write/verify passed against that build using the explicit local
  fixture `make -f Makefile -f tmp/receipt-fixture.mk image-receipt verify-image-receipt ENV=test-harness-adopt`;
  its successful job results are simulated, not CI evidence. Repeating verification with
  `GITHUB_RUN_ATTEMPT=2` correctly fails with `Image receipt does not match this image, SHA, run and attempt`.
- `attention` Lot 3: remote CI is unverified because pushing/opening a PR is forbidden in this task.
  Owner: conductor; acceptance: all CI jobs pass on the PR after the engine Clippy warnings are resolved.
- Review inputs: two independent completed reviews, `tmp/packets/review-pr1-astra.md.out` and
  `tmp/packets/review-pr1-argon.md.out` (relative to the root checkout); both require changes.

## Review outcomes

Finding IDs below use the reviewer's numbering; outcomes are recorded as each correction is verified.

| Finding | Priority | Outcome | Evidence / remaining acceptance |
| --- | --- | --- | --- |
| Argon P1-5 | P1 | fixed | Scope reflects touched files; EX6 declared; Track remains unchecked. ENV isolation and final gate evidence follow below. |
| Astra 1, 2, 3; Argon P0-1 (local policy) | P1 / P0 | fixed | Shared identifiers, effective hook identities, checked Git/message reads; regression suite follows. All bots, including dependabot, require human re-authorship; no unverifiable dependency-only exception. |
| Attribution regression coverage | P1 | fixed | `make test-attribution`: marker vocabulary, human discussion, both identities, config overrides, commit objects, read/Git/grep failures. |
| Argon P1-3 | P1 | fixed | Raw MSG exported; file-based commit, single-line validation, signing disabled for headless commits; quotes/dollars/backticks/backslashes tested. SQL/PATTERN transport corrected with operational targets. |
| Argon P0-2 | P0 | fixed | Settings allow Make, selective staging and read-only Git; direct toolchains/Python/commit/push/filter-branch and stale paths removed. Attribution-off keys retained. |

## Plan / Todo (lot-based)
- [ ] **Lot 0 — Baseline & constraints**
  - [x] Backup bundle of all refs before purge, ref `backup/pre-purge-main`.
  - [x] `purge/main-rewritten`: 6 commits `claude@anthropic.com` re-authored; per-commit tree/message/date equality verified.
  - [x] Current `main` is the rewritten base `b1a8f1f`; no push is authorized in this correction task.
- [ ] **Lot 1 — Governance and attribution guard**
  - [x] `AGENTS.md`, `CLAUDE.md`, `rules/MASTER.md`, `plan/BRANCH_TEMPLATE.md`, `harness.profile.json`.
  - [x] `tools/check-attribution.sh` + `.githooks/commit-msg`; tested: rejects a `Co-Authored-By` AI trailer and AI identities, passes the rewritten history.
  - [x] Makefile workflow targets (BR01-EX1); `LICENSE` MIT (BR01-EX2).
  - [x] `.claude/settings.json`: disable agent co-author attribution at the source.
  - [ ] `harness.profile.json` is declared but the host `harness` CLI only loads built-in profiles (`sentropic|stub`): `make scope-check` runs `--profile sentropic` until custom profiles are supported (request to the harness maintainer).
  - [ ] Lot gate: `make check-attribution` + `make check-no-python` + `make scope-check`.
- [x] **Lot 2 — Docker-first toolchain**
  - [x] `make build|test|lint|check` run in pinned Rust/Node images (digests); host toolchain no longer required.
  - [x] Branch verified as `chore/harness-adopt` with Git and `harness check branch` before implementation.
  - [x] BR01-EX5 consensus: box large errors in internal Raft helpers; preserve public OpenRaft trait signatures.
  - [x] BR01-EX5 operator: scope `double_must_use` suppression to `fetch`; async_trait generates the redundant attribute.
  - [x] BR01-EX5 SQL executor: mechanical aggregate lint fixes; remove obsolete `project_joined_row` (multi-join execution builds and pads rows directly).
  - [x] BR01-EX5 SQL parser: collapse conditions and remove the duplicate test attribute; record the existing CHARACTER VARYING gap above.
  - [x] Lot gate: `make -k check ENV=test-harness-adopt` green in containers.
- [ ] **Lot 3 — CI bootstrap (BR01-EX3)**
  - [x] Single image-receipt writer/verifier with negative tests (`make test-image-receipt ENV=test-harness-adopt`).
  - [x] Docker-only musl build, Alpine image smoke test, and Make entry points for receipt write/verify.
  - [x] Workflow: attribution guard on the PR range, no-python, lint, tests, TS; tested-artifact receipt for the image.
  - [x] `make check-ci ENV=test-harness-adopt`: actionlint passes; all actions pinned to full commit SHAs.
  - [x] Weekly Dependabot updates for npm, cargo, docker and github-actions.
  - [ ] Lot gate: CI green on the PR.
- [ ] **Lot 4 — Track (BR01-EX4)**
  - [ ] `track init`; import this `BRANCH.md`; workpackages from `docs/roadmap` (WP1–WP7).
- [ ] **Lot N — Final validation**
  - [ ] `make check`; PR body = this `BRANCH.md`; owner sign-off; remove `BRANCH.md` before merge.
