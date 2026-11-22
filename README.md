# sentbase

An MIT-licensed, self-deployable data platform: a Supabase-equivalent built step by step, ending with its own
database engine and no dependency on Supabase or PostgreSQL.

- **License:** MIT, for everything in this repository. No open-core, no dual licensing, no paid edition — never
  any license sold.
- **Engine:** the Rust engine under `crates/` (formerly the `opendb` repository, imported with its history). It
  speaks the PostgreSQL wire protocol for compatibility only.
- **Trajectory:** staged. The first distributions run on PostgreSQL behind the sentropic auth overlay; Supabase-like
  components are then replaced by MIT equivalents; the engine replaces PostgreSQL per tenant once it passes its
  parity, security and recovery gates.

## Status

Early. The harness (rules, scope control, commit discipline, CI) is being adopted; see `BRANCH.md` while a branch
is open, and `docs/roadmap/` for the engine roadmap.

## Working on this repository

Read `AGENTS.md` and `rules/MASTER.md` first. All commands go through `make` (`make help`). After cloning, run
`make hooks` once. Commits never carry AI/agent attribution.
