#!/usr/bin/env bash
# CI comment-policy scan (PR version of commit-guard's scan-comments.sh).
#
# Scans the diff between $BASE_SHA and $HEAD_SHA for any leading-line `//`,
# `/* */`, or `#` comments in source files. Allowed exceptions:
#
#   - TODO(@handle) / FIXME(@handle) single-line flags
#   - Tool pragmas: //go:build, // +build, // eslint-disable*, // ts-expect-error,
#     // @ts-*, # noqa, # type: ignore, # pylint:, # mypy:, // biome-ignore
#   - SPDX license headers, shebangs
#   - PHP: PHPDoc `/** */` blocks whose every content line is a static-analysis
#     annotation (@param, @return, @var, @property, @method, @template,
#     @extends, @implements, @mixin, @throws, @phpstan-*, @psalm-*)
#   - Config files: any path under a `config/` directory and
#     `*.config.{php,js,ts,mjs,cjs}`
#
# Output (stdout): <file>:<line>:<excerpt>
# Exit code: 0 no violations, 1 violations found

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

is_allowed_pragma() {
  local line="$1"
  case "$line" in
    *"TODO("*"@"*")"*) return 0 ;;
    *"FIXME("*"@"*")"*) return 0 ;;
    *"//go:build"*) return 0 ;;
    *"// +build"*) return 0 ;;
    *"// eslint-disable"*) return 0 ;;
    *"// eslint-enable"*) return 0 ;;
    *"// biome-ignore"*) return 0 ;;
    *"// @ts-"*) return 0 ;;
    *"// ts-expect-error"*) return 0 ;;
    *"# noqa"*) return 0 ;;
    *"# type: ignore"*) return 0 ;;
    *"# pylint:"*) return 0 ;;
    *"# mypy:"*) return 0 ;;
    *"# pragma"*) return 0 ;;
    *"SPDX-License-Identifier:"*) return 0 ;;
    "#!"*) return 0 ;;
  esac
  return 1
}

is_php_doc_tag() {
  local s="$1"
  case "$s" in
    "@param"*|"@return"*|"@var"*|"@property"*|"@property-read"*|"@property-write"*) return 0 ;;
    "@method"*|"@template"*|"@template-covariant"*|"@template-contravariant"*) return 0 ;;
    "@extends"*|"@implements"*|"@use"*|"@mixin"*|"@throws"*) return 0 ;;
    "@phpstan-"*|"@psalm-"*) return 0 ;;
  esac
  return 1
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue

  case "$f" in
    config/*|*/config/*) continue ;;
    *.config.php|*.config.js|*.config.ts|*.config.mjs|*.config.cjs) continue ;;
  esac

  is_php=0
  case "$f" in *.php) is_php=1 ;; esac

  hash_comment=0
  case "$f" in *.py|*.rb) hash_comment=1 ;; esac

  in_doc=0
  doc_start_ln=0
  doc_pure=1

  ln=0
  while IFS= read -r line; do
    ln=$((ln + 1))
    trimmed="${line#"${line%%[![:space:]]*}"}"

    if [ "$is_php" -eq 1 ] && [ "$in_doc" -eq 1 ]; then
      case "$trimmed" in
        *"*/"*)
          body="${trimmed%%\*/*}"
          body="${body#\*}"
          body=$(trim "$body")
          if [ -n "$body" ] && ! is_php_doc_tag "$body"; then
            doc_pure=0
          fi
          in_doc=0
          if [ "$doc_pure" -eq 0 ]; then
            echo "$f:$doc_start_ln: /** ... */ (narrative docblock)"
            violations=$((violations + 1))
          fi
          ;;
        *)
          content="${trimmed#\*}"
          content=$(trim "$content")
          if [ -n "$content" ] && ! is_php_doc_tag "$content"; then
            doc_pure=0
          fi
          ;;
      esac
      continue
    fi

    case "$trimmed" in
      "/**"*)
        if [ "$is_php" -eq 1 ]; then
          case "$trimmed" in
            *"*/"*)
              inner="${trimmed#/\*\*}"
              inner="${inner%%\*/*}"
              inner=$(trim "$inner")
              if [ -z "$inner" ] || is_php_doc_tag "$inner"; then
                continue
              fi
              echo "$f:$ln: $trimmed"
              violations=$((violations + 1))
              ;;
            *)
              in_doc=1
              doc_start_ln=$ln
              doc_pure=1
              rest="${trimmed#/\*\*}"
              rest=$(trim "$rest")
              if [ -n "$rest" ] && ! is_php_doc_tag "$rest"; then
                doc_pure=0
              fi
              ;;
          esac
          continue
        fi
        if is_allowed_pragma "$trimmed"; then
          continue
        fi
        echo "$f:$ln: $trimmed"
        violations=$((violations + 1))
        ;;
      "//"*|"/*"*)
        if is_allowed_pragma "$trimmed"; then
          continue
        fi
        echo "$f:$ln: $trimmed"
        violations=$((violations + 1))
        ;;
      "#"*)
        if [ "$hash_comment" -eq 0 ]; then
          continue
        fi
        if is_allowed_pragma "$trimmed"; then
          continue
        fi
        echo "$f:$ln: $trimmed"
        violations=$((violations + 1))
        ;;
    esac
  done < "$f"
done <<EOF
$files
EOF

if [ "$violations" -gt 0 ]; then
  exit 1
fi
exit 0
