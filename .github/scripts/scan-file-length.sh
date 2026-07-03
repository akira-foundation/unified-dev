#!/usr/bin/env bash
# CI file-length scan: blocks a PR only when it PUSHES a file over the 300-line
# cap (was <= 300 at the base ref, now > 300) or adds a brand-new file already
# over the cap. Files that were already over the cap before this PR touched
# them are left alone here, matching commit-guard's own "authorize pre-existing
# file-length" allowance rather than blocking unrelated legacy bloat.

set -uo pipefail

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "$repo_root" || exit 0

: "${BASE_SHA:?BASE_SHA must be set}"
: "${HEAD_SHA:?HEAD_SHA must be set}"

CAP=300

files=$(git diff --name-only --diff-filter=AM "$BASE_SHA...$HEAD_SHA" 2>/dev/null \
  | grep -E '\.(go|ts|tsx|js|jsx|mjs|cjs|php|rs|py|rb|swift|kt|java|cs|scala)$' || true)

if [ -z "$files" ]; then
  exit 0
fi

violations=0

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue

  head_lines=$(wc -l < "$f" | tr -d ' ')
  [ "$head_lines" -le "$CAP" ] && continue

  base_lines=$(git show "$BASE_SHA:$f" 2>/dev/null | wc -l | tr -d ' ')
  base_lines=${base_lines:-0}

  if [ "$base_lines" -le "$CAP" ]; then
    echo "$f: $head_lines lines > $CAP cap (was $base_lines at base, this PR pushed it over)"
    violations=$((violations + 1))
  fi
done <<EOF
$files
EOF

if [ "$violations" -gt 0 ]; then
  exit 1
fi

exit 0
