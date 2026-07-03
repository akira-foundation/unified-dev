#!/usr/bin/env bash
# CI chained-if scan (PR version of commit-guard's scan-chained-if.sh).
# Blocks `else if` / `elif` / `elsif` conditional chains in changed files.

set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$repo_root" || exit 0

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"

files=$(git diff --name-only --diff-filter=AM "$BASE_SHA...$HEAD_SHA" 2>/dev/null || true)

if [ -z "$files" ]; then
  exit 0
fi

violations=0

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue

  ln=0
  previous_else_line=0

  while IFS= read -r line; do
    ln=$((ln + 1))
    trimmed="${line#"${line%%[![:space:]]*}"}"

    if printf '%s\n' "$trimmed" | grep -Eq '(^|[^[:alnum:]_])(else[[:space:]]+if|elif|elsif)([^[:alnum:]_]|$)'; then
      echo "$f:$ln: $trimmed"
      violations=$((violations + 1))
    fi

    if [ "$previous_else_line" -gt 0 ] && printf '%s\n' "$trimmed" | grep -Eq '^if([^[:alnum:]_]|$)'; then
      echo "$f:$previous_else_line-$ln: else followed by if"
      violations=$((violations + 1))
    fi

    if printf '%s\n' "$trimmed" | grep -Eq '^else[[:space:]]*$'; then
      previous_else_line=$ln
    else
      previous_else_line=0
    fi
  done < "$f"
done <<EOF
$files
EOF

if [ "$violations" -gt 0 ]; then
  exit 1
fi

exit 0
