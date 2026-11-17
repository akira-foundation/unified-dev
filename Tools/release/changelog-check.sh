#!/bin/zsh
set -euo pipefail

repository="${1:-.}"
config="${2:-$repository/cliff.toml}"
config="${config:A}"
cd "$repository"

command -v git-cliff >/dev/null || { echo "changelog-check: git-cliff is not installed" >&2; exit 1; }

previous="$(git describe --tags --abbrev=0 --match 'v[0-9]*' HEAD 2>/dev/null || true)"
[ -n "$previous" ] || { echo "changelog-check: no release tag behind HEAD to compare against" >&2; exit 1; }

notes="$(git-cliff --config "$config" --use-branch-tags --unreleased --strip all 2>/dev/null)"
published_refs=(HEAD)
if git remote get-url origin >/dev/null 2>&1; then
  git fetch -q origin main || { echo "changelog-check: could not fetch origin/main, so what it published is unknown" >&2; exit 1; }
  published_refs+=(origin/main)
fi

published=""
for ref in "${published_refs[@]}"; do
  if git cat-file -e "$ref:CHANGELOG.md" 2>/dev/null; then
    published+="$(git show "$ref:CHANGELOG.md")"$'\n'
  fi
done
[ -n "$published" ] || { echo "changelog-check: no CHANGELOG.md on ${published_refs[*]} to compare against" >&2; exit 1; }

entries() {
  sed -nE '/^- /{s/ \(\[[0-9a-f]{7}\]\([^)]*\)\)$//;p;}' <<< "$1"
}

numbers() {
  sed -nE 's/.*\(#([0-9]+)\)$/\1/p' <<< "$1"
}

published_entries="$(entries "$published")"
published_numbers="$(numbers "$published_entries")"

conventional='^[A-Za-z]+(\([^)]*\))?!?: [^[:space:]]'
skipped='^(docs|style|test|ci|chore)(\([^)]*\))?: '
first_parent="$(git rev-list --first-parent --no-merges "$previous..HEAD")"
missing=()
inside_merges=()
listed=0

while IFS=$'\t' read -r sha subject; do
  [ -n "$sha" ] || continue
  [[ "$subject" =~ $skipped ]] && continue
  short="${sha[1,7]}"
  if grep -qF -- "[$short]" <<< "$notes"; then
    listed=$((listed + 1))
    continue
  fi
  reason="not in the notes"
  [[ "$subject" =~ $conventional ]] || reason="not a conventional commit, so git-cliff drops it"
  if grep -qx -- "$sha" <<< "$first_parent"; then
    missing+=("$short $subject ($reason)")
  else
    inside_merges+=("$short $subject ($reason)")
  fi
done < <(git log --no-merges --format='%H%x09%s' "$previous..HEAD")

if (( ${#inside_merges} > 0 )); then
  echo "changelog-check: inside merged branches, these commits will not reach the changelog either; read them, they block nothing:" >&2
  printf '  %s\n' "${inside_merges[@]}" >&2
fi

repeated=()
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  number="$(numbers "$entry")"
  if grep -qxF -- "$entry" <<< "$published_entries" \
    || { [ -n "$number" ] && grep -qxF -- "$number" <<< "$published_numbers"; }; then
    repeated+=("$entry")
  fi
done < <(entries "$notes")

if (( ${#missing} == 0 && ${#repeated} == 0 )); then
  echo "changelog-check: ${previous}..HEAD: ${listed} for the notes, all of them there, none already published."
  exit 0
fi

if (( ${#missing} > 0 )); then
  echo "changelog-check: since ${previous}, these commits will not reach the changelog:" >&2
  printf '  %s\n' "${missing[@]}" >&2
fi
if (( ${#repeated} > 0 )); then
  echo "changelog-check: the notes repeat entries an earlier release already published:" >&2
  printf '  %s\n' "${repeated[@]}" >&2
fi
exit 1
