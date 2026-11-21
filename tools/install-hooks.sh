#!/bin/sh
# Install the commit-msg attribution guards (make hooks).
# - With the machine h2a installer: its strip-mode guard in <git-common-dir>/hooks (worktree- and
#   branch-independent), chained through commit-msg.local to this repository's stricter
#   .githooks/commit-msg (reject mode, author/committer identity checks).
# - Without it: core.hooksPath=.githooks (repository guard only).
set -eu
installer="${H2A_TRAILER_GUARD:-$HOME/.npm-global/lib/node_modules/@sentropic/h2a/scripts/install-trailer-guard.mjs}"
top=$(git rev-parse --show-toplevel)
if [ -f "$installer" ]; then
  node "$installer" --local --repo "$top" --mode strip >/dev/null
  hooks_dir=$(git config core.hooksPath)
  cat > "$hooks_dir/commit-msg.local" <<'HOOK'
#!/usr/bin/env bash
# sentbase: chain the repository's own stricter attribution guard when the branch ships it.
set -euo pipefail
top="$(git rev-parse --show-toplevel)"
if [ -x "$top/.githooks/commit-msg" ]; then
  exec "$top/.githooks/commit-msg" "$@"
fi
exit 0
HOOK
  chmod +x "$hooks_dir/commit-msg.local"
  echo "hooks: h2a guard (strip) in $hooks_dir, chained to .githooks/commit-msg"
else
  git config core.hooksPath .githooks
  echo "hooks: core.hooksPath=.githooks"
fi
