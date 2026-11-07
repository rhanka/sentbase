#!/bin/sh
set -eu
[ -n "${MSG:-}" ] || { echo 'MSG is required' >&2; exit 1; }
[ "$(git config core.hooksPath)" = '.githooks' ] || { echo 'Run make hooks first' >&2; exit 1; }
if git diff --cached --quiet; then
  echo 'Nothing staged: git add <specific-files> first' >&2; exit 1
else
  status=$?
  [ "$status" -eq 1 ] || exit "$status"
fi
message_file=$(mktemp)
trap 'rm -f "$message_file"' EXIT HUP INT TERM
printf '%s\n' "$MSG" > "$message_file"
[ "$(wc -l < "$message_file")" -eq 1 ] || { echo 'MSG must be a single line' >&2; exit 1; }
case "$MSG" in *"$(printf '\r')"*) echo 'MSG must not contain carriage returns' >&2; exit 1;; esac
git -c commit.gpgsign=false commit --cleanup=verbatim -F "$message_file"
