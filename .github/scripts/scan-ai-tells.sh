#!/usr/bin/env bash
# CI AI-tells scan: blocks emojis, em-dashes, and a small set of AI-shaped
# filler phrases in added lines. Parses the unified diff itself (via python3)
# to track file+line per added line, since grep on raw diff text loses that
# context. python3 is used for the matching too, since grep's Unicode support
# is inconsistent between GNU (CI) and BSD (local macOS) builds.

set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$repo_root" || exit 0

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"

git diff "$BASE_SHA...$HEAD_SHA" -- . \
  ':(exclude)*.lock' ':(exclude)*lock.json' ':(exclude)*.svg' \
  ':(exclude).github/scripts/*.sh' ':(exclude)*.yml' ':(exclude)*.yaml' \
  | python3 -c '
import re, sys

em_dash = re.compile("—")
emoji = re.compile("[\U0001F300-\U0001FAFF☀-➿]")
banned = re.compile(
    r"in today.s fast-paced world|delve into|leverage the power of|it.s important to note that",
    re.IGNORECASE,
)

current_file = None
current_line = 0
violations = 0

for raw in sys.stdin:
    line = raw.rstrip("\n")
    if line.startswith("+++ "):
        path = line[4:]
        current_file = path[2:] if path.startswith("b/") else path
        continue
    hunk = re.match(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)
    if hunk:
        current_line = int(hunk.group(1))
        continue
    if line.startswith("+") and not line.startswith("+++"):
        content = line[1:]
        if current_file and em_dash.search(content):
            print(f"::error file={current_file},line={current_line}::em-dash in added line: {content.strip()}")
            violations += 1
        if current_file and emoji.search(content):
            print(f"::error file={current_file},line={current_line}::emoji in added line: {content.strip()}")
            violations += 1
        if current_file and banned.search(content):
            print(f"::error file={current_file},line={current_line}::AI-shaped filler phrase: {content.strip()}")
            violations += 1
        current_line += 1
    elif line.startswith("-") and not line.startswith("---"):
        continue
    elif not line.startswith("\\"):
        current_line += 1

sys.exit(1 if violations > 0 else 0)
'
