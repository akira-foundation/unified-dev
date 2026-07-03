#!/usr/bin/env bash
# CI chained-if scan (PR version of commit-guard's scan-chained-if.sh).
# Blocks else-if / elif / elsif conditional chains in changed source files.
# Scoped to code files only (not scripts, workflows, or docs), otherwise the
# regex matches its own definition text and other prose mentioning the word.

set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$repo_root" || exit 0

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"

files=$(git diff --name-only --diff-filter=AM "$BASE_SHA...$HEAD_SHA" 2>/dev/null \
  | grep -E '\.(go|ts|tsx|js|jsx|mjs|cjs|php|rs|py|rb|swift|kt|java|cs|scala)$' || true)

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
      echo "::error file=$f,line=$ln::chained if/elif/elsif: $trimmed"
      violations=$((violations + 1))
    fi

    if [ "$previous_else_line" -gt 0 ] && printf '%s\n' "$trimmed" | grep -Eq '^if([^[:alnum:]_]|$)'; then
      echo "::error file=$f,line=$ln::else immediately followed by if (chain starting at line $previous_else_line)"
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
