# Chore: adopt the sentropic harness in sentbase (opendb import)

## Objective
Bring sentbase (which absorbs the opendb repository and history) under the sentropic harness (rules, scope control, make-only, commit discipline, Track, CI) and make
AI/agent attribution in commits mechanically impossible, after the owner-approved history purge.

## Scope / Guardrails
- Scope limited to governance files, the attribution guard, Makefile workflow targets and CI bootstrap.
- No engine behaviour change: `crates/**` only for lint-only fixes under BR01-EX5. Make-only; worktree `tmp/chore-harness-adopt`.
- Built on `purge/main-rewritten` (6 AI-authored commits re-authored, trees identical); rebased onto `main`
  if the owner does not approve the force-push.
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
  - `tools/image-receipt.mjs`
  - `tools/image-receipt.test.mjs`
  - `.github/dependabot.yml`
  - `.githooks/**`
  - `.claude/settings.json`
  - `.gitignore`
  - `README.md`
- **Forbidden Paths (must not change in this branch)**:
  - `Cargo.toml`
  - `Cargo.lock`
- **Conditional Paths (allowed only with explicit exception when not already listed in Allowed Paths)**:
  - `Makefile` (BR01-EX1)
  - `LICENSE` (BR01-EX2)
  - `.github/workflows/**` (BR01-EX3)
  - `.track/**` (BR01-EX4)
  - `crates/**/*.rs` (BR01-EX5, lint-only)
- **Exception process**:
  - Declare exception ID `BRxx-EXn` in `## Feedback Loop` before touching any conditional/forbidden path.

## Feedback Loop
- `BR01-EX1` Makefile: replace hardcoded worktree path by `$(CURDIR)`; replace `commit`/`ship` (which ran
  `git add -A` and pushed to main) by hook-enforced `commit`, branch-only `push`, `hooks`, `check-attribution`,
  `scope-check`; run quality targets in digest-pinned Rust/Node images with worktree-local caches,
  and build the musl binary/image plus verify its receipt through Make. Impact: workflow targets only.
  Rollback: revert the commit.
- `BR01-EX2` LICENSE: add MIT (owner direction 2026-11-06: full MIT, never any sold license). Impact: the repo
  had no license. Rollback: none intended (license grants are not revocable once published).
- `BR01-EX3` CI: add a first GitHub Actions workflow (attribution guard, no-python, lint, tests, TS,
  image receipt) and weekly Dependabot updates. Impact: validation only, no publication. Rollback: revert.
- `BR01-EX4` Track: `track init` for opendb realization state. Rollback: revert.
- `BR01-EX5` Engine lint debt: `make clippy` (-D warnings) fails on `main` (~22 errors in wal.rs, raft.rs,
  recovery.rs, executor.rs, parser.rs). Fix them without behaviour change so CI can be green. Impact: engine
  source, lint-only; all Rust tests must still pass. Rollback: revert the commits.
- `attention` Lot 2: `make check ENV=test-harness-adopt` fails at Clippy in
  `crates/opendb-storage/src/wal.rs`: `clippy::type_complexity` at line 175 and
  `clippy::unnecessary_cast` at lines 911, 965, 1017. Engine changes are forbidden;
  reproduced on an unmodified `git archive main` snapshot (main `b1a8f1f`) with
  `make -C tmp/main-baseline -f ../../Makefile clippy ENV=test-harness-baseline`.
  Owner: engine maintainer; bounded fix: these warnings; acceptance: `make clippy` passes.
  Other gates pass with `make -k check ENV=test-harness-adopt` (331 Rust + 38 Vitest tests).
- Toolchain licenses: official Node (MIT), Rust (MIT OR Apache-2.0), actionlint (MIT); no new package dependency.
- Image validation: `make image ENV=test-harness-adopt` builds `Dockerfile.alpine` and runs its immutable
  image ID with `--help`. Receipt CLI write/verify passed against that build using the explicit local
  fixture `make -f Makefile -f tmp/receipt-fixture.mk image-receipt verify-image-receipt ENV=test-harness-adopt`;
  its successful job results are simulated, not CI evidence. Repeating verification with
  `GITHUB_RUN_ATTEMPT=2` correctly fails with `Image receipt does not match this image, SHA, run and attempt`.
- `attention` Lot 3: remote CI is unverified because pushing/opening a PR is forbidden in this task.
  Owner: conductor; acceptance: all CI jobs pass on the PR after the engine Clippy warnings are resolved.
- `attention` Review: peer selection is pending exact author model/effort metadata (the handoff only
  names Sol); the review skill refuses unknown author metadata. Owner: conductor; acceptance: two eligible
  completed peer reviews. Local dossier: `tmp/lot-2-3-review.md`; no consensus verdict is claimed.

## Plan / Todo (lot-based)
- [ ] **Lot 0 — Baseline & constraints**
  - [x] Backup bundle of all refs before purge, ref `backup/pre-purge-main`.
  - [x] `purge/main-rewritten`: 6 commits `claude@anthropic.com` re-authored; per-commit tree/message/date equality verified.
  - [ ] Owner GO for force-push of `main` (and closing the 3 dependabot branches based on the old tip).
- [ ] **Lot 1 — Governance and attribution guard**
  - [x] `AGENTS.md`, `CLAUDE.md`, `rules/MASTER.md`, `plan/BRANCH_TEMPLATE.md`, `harness.profile.json`.
  - [x] `tools/check-attribution.sh` + `.githooks/commit-msg`; tested: rejects a `Co-Authored-By` AI trailer and AI identities, passes the rewritten history.
  - [x] Makefile workflow targets (BR01-EX1); `LICENSE` MIT (BR01-EX2).
  - [x] `.claude/settings.json`: disable agent co-author attribution at the source.
  - [ ] `harness.profile.json` is declared but the host `harness` CLI only loads built-in profiles (`sentropic|stub`): `make scope-check` runs `--profile sentropic` until custom profiles are supported (request to the harness maintainer).
  - [ ] Lot gate: `make check-attribution` + `make check-no-python` + `make scope-check`.
- [ ] **Lot 2 — Docker-first toolchain**
  - [x] `make build|test|lint|check` run in pinned Rust/Node images (digests); host toolchain no longer required.
  - [x] Branch verified as `chore/harness-adopt` with Git and `harness check branch` before implementation.
  - [ ] Lot gate: `make check` green in containers.
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
