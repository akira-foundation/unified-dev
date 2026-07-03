#!/usr/bin/env bash
# CI AI-tells scan: blocks emojis and em-dashes in added lines, plus a small
# set of AI-shaped filler phrases. Scans only added (+) lines in the PR diff.
# Uses python3 for the Unicode matching (em-dash, emoji) since grep's Unicode
# support is inconsistent between GNU (CI) and BSD (local macOS) builds.

set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$repo_root" || exit 0

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"

violations=0

added_lines=$(git diff "$BASE_SHA...$HEAD_SHA" -- . ':(exclude)*.lock' ':(exclude)*lock.json' ':(exclude)*.svg' \
  | grep -E '^\+[^+]')

if [ -z "$added_lines" ]; then
  exit 0
fi

unicode_hits=$(printf '%s\n' "$added_lines" | python3 -c '
import re, sys
em_dash = re.compile("—")
emoji = re.compile("[\U0001F300-\U0001FAFF☀-➿]")
for line in sys.stdin:
    if em_dash.search(line):
        print("em-dash: " + line.rstrip())
    if emoji.search(line):
        print("emoji: " + line.rstrip())
')

if [ -n "$unicode_hits" ]; then
  echo "$unicode_hits" | head -40
  violations=$((violations + 1))
fi

banned_phrases='in today.s fast-paced world|delve into|leverage the power of|it.s important to note that'
if printf '%s\n' "$added_lines" | grep -Eiq "$banned_phrases"; then
  echo "AI-shaped filler phrase found in added lines"
  printf '%s\n' "$added_lines" | grep -Ei "$banned_phrases" | head -20
  violations=$((violations + 1))
fi

if [ "$violations" -gt 0 ]; then
  exit 1
fi

exit 0
