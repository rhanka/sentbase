# AI Assistant Bootstrap

Read `rules/MASTER.md` before any action. It contains the consolidated project rules (sentropic harness).

## Mandatory read order
1. `rules/MASTER.md` — consolidated rules (always)
2. `plan/BRANCH_TEMPLATE.md` — when creating or updating a `BRANCH.md`

## Quick reference
- All commands via `make` targets only
- Branch work in `tmp/<slug>` worktrees, never on the root checkout
- `make hooks` once per clone; commits only via `make commit MSG="type: message"`
- Commits never carry AI/agent attribution (enforced by `.githooks/commit-msg` and CI `make check-attribution`)
- Zero Python, anywhere (`make check-no-python`)

## Scope & branch discipline — use `harness` (mandatory)
- `make scope-check` before every commit: local changes vs the branch `BRANCH.md`
- `harness check branch ...` before any work on a worktree (host CLI: `npm i -g @sentropic/harness`)
