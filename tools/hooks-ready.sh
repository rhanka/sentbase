#!/bin/sh
# Succeed only when commits run this repository's attribution guard (.githooks/commit-msg).
set -eu
top=$(git rev-parse --show-toplevel)
path=$(git config core.hooksPath || true)
[ "$path" = '.githooks' ] && [ -x "$top/.githooks/commit-msg" ] && exit 0
[ -n "$path" ] && [ -x "$path/commit-msg" ] && [ -x "$path/commit-msg.local" ] \
  && grep -q '.githooks/commit-msg' "$path/commit-msg.local" && [ -x "$top/.githooks/commit-msg" ] && exit 0
exit 1
