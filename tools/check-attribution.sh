#!/bin/sh
# Refuse any AI/agent attribution in commits (owner rule: commits carry no AI attribution, ever).
#   tools/check-attribution.sh --message-file <file>   # commit-msg hook mode
#   tools/check-attribution.sh <rev-range>             # history mode, e.g. origin/main..HEAD or --all
set -eu
TRAILER_RE='^(co-authored-by|claude-session|generated-by|signed-off-by)[[:space:]]*:.*(claude|anthropic|openai|codex|chatgpt|gpt-[0-9]|gemini|copilot|cursor|mistral|vibe|muse|llm|ai assistant)'
MARKER_RE='(generated with \[?(claude|codex|copilot|gemini|cursor)|claude\.com/claude-code|noreply@anthropic\.com|🤖)'
IDENT_RE='(anthropic\.com|openai\.com|claude@|codex@|copilot@|gemini@)'

check_message() { # $1 = label, stdin = message
  bad=$(grep -i -n -E "$TRAILER_RE|$MARKER_RE" || true)
  if [ -n "$bad" ]; then echo "attribution-guard: AI attribution in $1:" >&2; echo "$bad" >&2; return 1; fi
}

if [ "${1:-}" = "--message-file" ]; then
  grep -v '^#' "$2" | check_message "commit message" || {
    echo "attribution-guard: remove the line(s) above; commits never carry AI/agent attribution." >&2; exit 1; }
  for v in "${GIT_AUTHOR_EMAIL:-}" "${GIT_COMMITTER_EMAIL:-}" "$(git config user.email || true)"; do
    if printf '%s' "$v" | grep -q -i -E "$IDENT_RE"; then echo "attribution-guard: AI identity '$v' refused." >&2; exit 1; fi
  done
  exit 0
fi

range="${1:?usage: check-attribution.sh <rev-range>|--all|--message-file <file>}"
fail=0
for c in $(git rev-list $range); do
  git show -s --format=%B "$c" | check_message "commit $c" || fail=1
  ident=$(git show -s --format='%an <%ae> | %cn <%ce>' "$c")
  if printf '%s' "$ident" | grep -q -i -E "$IDENT_RE"; then echo "attribution-guard: AI identity on $c: $ident" >&2; fail=1; fi
done
[ "$fail" -eq 0 ] && echo "attribution-guard: OK ($(git rev-list --count $range) commits in $range)"
exit "$fail"
