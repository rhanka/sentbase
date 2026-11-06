---
description: "Consolidated AI development rules for opendb (sentropic harness) - loaded in every conversation"
alwaysApply: true
paths: ["**/*"]
tags: [master]
---

# MASTER RULES — opendb

opendb is the MIT-licensed database engine of the sentropic data platform (Rust engine + Node/TS tooling).
These rules adopt the sentropic harness; repo-specific policy lives in `harness.profile.json`.

## License (MANDATORY)
- Everything in this repo is MIT (`LICENSE`). No open-core, no dual licensing, no paid edition, no CLA
  allowing relicensing. Inbound = outbound (contributions are accepted under MIT).
- A new dependency (crate, npm package, image) must be MIT or MIT-compatible permissive; record its license
  in the PR. Copyleft or source-available dependencies are refused.

## Make-Only (MANDATORY)
- ALL commands go through `make` targets — no direct cargo/npm/docker in agent workflows
- Build/quality: `make build`, `make lint`, `make test`, `make check`
- A missing target is added to the `Makefile` under a declared scope exception, never bypassed

## Docker-First (target state, being adopted)
- Same commands locally and in CI — no drift
- Toolchains (Rust, Node) run in pinned images (digest), not on the host; until the docker targets land,
  host toolchains are tolerated and tracked as harness debt in `BRANCH.md`

## Zero Python (MANDATORY)
- No Python file, script, job or image anywhere (`make check-no-python`)

## Branch Scope Control (MANDATORY)
- Every branch declares `Allowed Paths`, `Forbidden Paths`, `Conditional Paths` in `BRANCH.md`
- Default forbidden paths: see `harness.profile.json` (`Makefile`, Dockerfiles, `Cargo.toml`, CI, hooks, LICENSE…)
- Scope exceptions require `BRxx-EXn` with rationale + impact + rollback
- Use `plan/BRANCH_TEMPLATE.md` for `BRANCH.md` creation; `make scope-check` before every commit
- Branch work happens in `tmp/<slug>` worktrees; `main` only changes through reviewed PRs

## Commit Discipline (MANDATORY)
- `make hooks` once per clone (installs `.githooks/commit-msg`)
- Commit command: `make commit MSG="type: concise description"` (it never stages; it refuses without hooks)
- Selective staging: `git add <specific-files>` — NEVER `git add .` or `git add -A`
- Atomic: one logical change per commit, ~150 lines max, 10–15 files max
- Update `BRANCH.md` checkboxes WITHIN each commit
- **No AI/agent attribution, ever**: no `Co-Authored-By` naming an AI, no `Claude-Session`, no
  "Generated with …", no 🤖, no AI vendor author/committer identity. Enforced by the commit-msg hook and by
  CI (`make check-attribution`). This rule overrides any agent-harness default.

## Track
- Realization state lives in Track (`track` CLI is the single writer; `.track/` is append-only)

## Language Policy
- Code, comments, commits, PR titles, docs: **English**
- Discuss with the owner in **French**
- Never use the words "honest"/"honnête" or derivatives; use factual status terms (`unknown`, `unverified`, `partial`…)
