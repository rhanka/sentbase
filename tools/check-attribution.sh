#!/bin/sh
# Local hook and history policy. CI extracts the base revision of this file.
set -eu
export LC_ALL=C

# One maintained vocabulary for attribution trailers, prose markers and identities.
AGENTS='claude|anthropic|openai|chatgpt|codex|copilot|gemini|cursor(agent)?|mistral|vibe|muse|devin|aider|windsurf|codeium|cline|roo|jules|junie|amp|antigravity|sonnet|opus|haiku|gpt-[0-9]+|o[134](-mini|-pro)?|llm|ai[- ]?(assistant|agent)'
AGENT_RE="(^|[^[:alnum:]])($AGENTS)([^[:alnum:]]|$)"
TRAILER_RE="^[[:space:][:punct:]]*(co-authored-by|generated-by|signed-off-by|assisted-by|authored-by|reviewed-by|suggested-by|helped-by)[[:space:]*_]*:([[:space:][:punct:]]*|.*[^[:alnum:]])($AGENTS)([^[:alnum:]]|$)"
MARKER_RE="(generated|written|created|authored|built)[[:space:][:punct:]]+(with|by)[[:space:][:punct:]]+($AGENTS)([^[:alnum:]]|$)"
MESSAGE_RE="$TRAILER_RE|$MARKER_RE|claude-session[[:space:]]*:|claude\.com/claude-code|🤖"

die() { echo "attribution-guard: $*" >&2; exit 1; }
matches() {
  # grep errors must not become normal non-matches.
  if printf '%s\n' "$1" | grep -iE "$2" >/dev/null; then return 0; else
    status=$?
    [ "$status" -eq 1 ] || die "pattern inspection failed ($status)"
    return 1
  fi
}
check_message() {
  if matches "$1" "$MESSAGE_RE"; then die "attribution in $2"; fi
}
check_identity() {
  # No bot exception: dependabot commits also require human re-authorship.
  if matches "$1" "$AGENT_RE|\[bot\]"; then die "agent/bot identity in $2"; fi
}

if [ "${1:-}" = '--message-file' ]; then
  [ "$#" -eq 2 ] || die 'expected --message-file <file|->'
  if [ "$2" = '-' ]; then
    message=$(cat) || die 'cannot read message stdin'
  else
    message=$(cat -- "$2") || die 'cannot read message file'
  fi
  # A verbose diff after the scissors marker is not part of the message.
  message=$(printf '%s\n' "$message" | sed '/^# ------------------------ >8 ------------------------$/,$d') || die 'cannot prepare message'
  check_message "$message" 'commit message'
  author=$(git var GIT_AUTHOR_IDENT) || die 'cannot resolve author'
  committer=$(git var GIT_COMMITTER_IDENT) || die 'cannot resolve committer'
  check_identity "$author" author
  check_identity "$committer" committer
  exit 0
fi

[ "$#" -eq 1 ] || die 'expected a revision range or --all'
range=$1
case "$range" in --all) ;; -*) die 'unsupported revision option' ;; esac
commits=$(git rev-list "$range") || die 'cannot enumerate revision range'
count=0
for commit in $commits; do
  message=$(git show -s --format=%B "$commit") || die 'cannot read commit message'
  check_message "$message" "commit $commit"
  for field in an ae cn ce; do
    identity=$(git show -s --format="%$field" "$commit") || die 'cannot read commit identity'
    check_identity "$identity" "$field on $commit"
  done
  count=$((count + 1))
done
echo "attribution-guard: OK ($count commits in $range)"
