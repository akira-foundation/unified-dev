#!/bin/zsh
set -euo pipefail

root="${0:A:h}/../../.."
check="$root/Tools/release/changelog-check.sh"
real_config="${1:-$root/cliff.toml}"
real_config="${real_config:A}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

command -v git-cliff >/dev/null || { echo "changelog-check test: git-cliff is not installed" >&2; exit 1; }

export GIT_AUTHOR_NAME=release-test GIT_AUTHOR_EMAIL=release-test@example.invalid
export GIT_COMMITTER_NAME=release-test GIT_COMMITTER_EMAIL=release-test@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

clock=1767225600

commit() {
  clock=$((clock + 60))
  GIT_AUTHOR_DATE="@$clock" GIT_COMMITTER_DATE="@$clock" git -C "$1" commit -q --allow-empty -m "$2"
}

released_repository() {
  repo="$(mktemp -d "$work/repository.XXXXXX")"
  git init -q -b develop "$repo"
  commit "$repo" "feat: the first release"
  git -C "$repo" tag v1.2.0
  git -C "$repo" checkout -q -b release/1.2.1
  commit "$repo" "fix(composer): show the version each Claude alias runs (#515)"
  git -C "$repo" tag v1.2.1
  git-cliff --config "$real_config" --repository "$repo" --use-branch-tags --output "$repo/CHANGELOG.md" 2>/dev/null
  git -C "$repo" add CHANGELOG.md
  commit "$repo" "chore(changelog): v1.2.1"
  git -C "$repo" checkout -q develop
}

merged_back() {
  clock=$((clock + 60))
  GIT_AUTHOR_DATE="@$clock" GIT_COMMITTER_DATE="@$clock" \
    git -C "$1" merge -q --no-ff -m "Merge pull request #529 from example/chore/merge-back-v1.2.1" release/1.2.1
}

run_check() {
  "$check" "$1" "${2:-$real_config}" 2>&1
}

fail() {
  echo "changelog-check test: $1" >&2
  exit 1
}

released_repository
merged_back "$repo"
commit "$repo" "feat(bridge): let any workspace reach another orchestrator (#560)"
commit "$repo" "docs: say how a release is cut (#561)"
output="$(run_check "$repo")" || fail "a clean range was refused: $output"
[[ "$output" == *"v1.2.1..HEAD: 1 for the notes"* ]] || fail "a clean range did not count its one entry: $output"

released_repository
merged_back "$repo"
commit "$repo" "feat(bridge): let any workspace reach another orchestrator (#560)"
commit "$repo" "Run Antigravity CLI agents over ACP (#630)"
if output="$(run_check "$repo")"; then fail "an unconventional squash subject went through: $output"; fi
[[ "$output" == *"Run Antigravity CLI agents over ACP (#630) (not a conventional commit"* ]] \
  || fail "the unconventional subject is not named: $output"
[[ "$output" != *"(#560)"* ]] || fail "a conventional entry was reported: $output"

released_repository
commit "$repo" "fix(composer): show the version each Claude alias runs (#515)"
merged_back "$repo"
if output="$(run_check "$repo")"; then fail "a fix already published in 1.2.1 went through again: $output"; fi
[[ "$output" == *"repeat entries an earlier release already published"* && "$output" == *"(#515)"* ]] \
  || fail "the repeated fix is not named: $output"

released_repository
commit "$repo" "fix(composer): show which version each Claude alias runs (#515)"
merged_back "$repo"
if output="$(run_check "$repo")"; then fail "a reworded copy of a published fix went through: $output"; fi
[[ "$output" == *"(#515)"* ]] || fail "the reworded copy is not named by its number: $output"

released_repository
merged_back "$repo"
commit "$repo" "chore!: drop the old settings file (#570)"
output="$(run_check "$repo")" || fail "a breaking chore listed in the notes was refused: $output"
[[ "$output" == *"v1.2.1..HEAD: 1 for the notes"* ]] || fail "a breaking chore was not counted: $output"

released_repository
merged_back "$repo"
git -C "$repo" checkout -q -b feat/readme
commit "$repo" "Bring the README in line with the pattern"
git -C "$repo" checkout -q develop
clock=$((clock + 60))
GIT_AUTHOR_DATE="@$clock" GIT_COMMITTER_DATE="@$clock" \
  git -C "$repo" merge -q --no-ff -m "Merge pull request #440 from example/feat/readme" feat/readme
if output="$(run_check "$repo")"; then fail "an unconventional commit inside a merged pull request went through: $output"; fi
[[ "$output" == *"Bring the README in line with the pattern (not a conventional commit"* ]] \
  || fail "the commit inside the merge is not named: $output"

repo="$(mktemp -d "$work/repository.XXXXXX")"
git init -q -b develop "$repo"
commit "$repo" "feat: the first release"
git -C "$repo" tag v1.2.0
commit "$repo" "fix: a fix after it (#600)"
if output="$(run_check "$repo")"; then fail "a range with no published changelog to compare against went through: $output"; fi
[[ "$output" == *"no CHANGELOG.md"* ]] || fail "the missing changelog is not named: $output"

skipping_features="$work/skipping-features.toml"
sed 's/{ message = "^feat", group = "Features" }/{ message = "^feat", group = "Features", skip = true }/' "$real_config" > "$skipping_features"
released_repository
merged_back "$repo"
commit "$repo" "feat(bridge): let any workspace reach another orchestrator (#560)"
if output="$(run_check "$repo" "$skipping_features")"; then fail "a conventional entry missing from the notes went through: $output"; fi
[[ "$output" == *"(#560) (not in the notes)"* ]] || fail "the entry missing from the notes is not named: $output"

released_repository
origin="$(mktemp -d "$work/origin.XXXXXX")"
git init -q --bare "$origin"
git -C "$repo" remote add origin "$origin"
git -C "$repo" push -q origin release/1.2.1:main
commit "$repo" "fix(composer): show the version each Claude alias runs (#515)"
if output="$(run_check "$repo")"; then fail "a fix published only on origin/main went through again: $output"; fi
[[ "$output" == *"(#515)"* ]] || fail "the fix published on origin/main is not named: $output"

released_repository
merged_back "$repo"
commit "$repo" "feat(bridge): let any workspace reach another orchestrator (#560)"
git -C "$repo" tag v1.3.0-beta.1
commit "$repo" "fix(bridge): answer the orchestrator once (#562)"
output="$(run_check "$repo")" || fail "a range after a prerelease tag was refused: $output"
[[ "$output" == *"v1.3.0-beta.1..HEAD: 1 for the notes"* ]] || fail "the prerelease tag is not where the range starts: $output"

echo "changelog-check: an unconventional subject and an entry already published are both refused, and a clean range passes."
