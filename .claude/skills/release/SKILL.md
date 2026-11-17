---
name: unifieddev-release
description: Release Unified Dev by pushing a version tag, which generates the changelog and release notes and publishes signed artefacts on GitHub, or create signed local release artefacts. Use when asked to cut, ship, publish, or prepare a Unified Dev release.
---

# Release Unified Dev

Run app commands from this repository root. `.github/workflows/release.yml` is the pipeline and
`cliff.toml` decides how commits become the changelog. Use `gh` for GitHub.

## Publish a release

A release is cut on its own branch. `release/<version>` is cut from `develop`, the tag goes on that
branch, the Release workflow commits `CHANGELOG.md` back to it, a pull request takes it into
`main`, and `main` is merged back into `develop`. Nothing is tagged on `develop` or on `main`.

1. Establish the intended commit and version. Inspect repository status, existing tags and
   releases, and CI for that commit. Do not release uncommitted code or infer success from a
   different commit's green run. Work out the version from the commits rather than choosing it:

   ```sh
   git-cliff --config cliff.toml --use-branch-tags --bumped-version
   ```

   The workflow refuses a stable tag that disagrees with it. Tags use `v1.4.0`, or `v1.4.0-beta.1`
   for a prerelease, which skips that check and publishes as a GitHub prerelease.

2. Cut the release branch from an up to date `develop`, without tracking it, and publish it:

   ```sh
   git fetch origin
   git checkout -b release/<version> --no-track origin/develop
   git push -u origin release/<version>
   ```

   Fixes for this release are pull requests into `release/<version>`.

3. **Check the changelog before the tag.** On the release branch, with `origin/main` fetched, run:

   ```sh
   ./Tools/release/changelog-check.sh
   ```

   It takes every commit on the first-parent line since the last stable tag, which is every pull
   request merged since that release, and compares it with what
   `git-cliff --config cliff.toml --use-branch-tags --unreleased --strip all` will write. It also
   compares every entry of those notes with `CHANGELOG.md` on `HEAD` and on `origin/main`. It exits
   non-zero and names each one when a pull request will not reach the notes, because its squash
   subject is not a conventional commit and `filter_unconventional` drops it, or when the notes
   repeat an entry an earlier release already published, which is a fix cherry-picked into a patch
   release whose original on `develop` does not descend from that tag.

   **If it fails, stop and do not tag.** Report the list to the owner. The repair is an entry in
   `cliff.toml`, by commit sha, through a pull request into the release branch, and which entry is
   the owner's decision. `develop`, `main` and published tags are never rewritten for it.

4. Tag the release branch and push the tag. Tagging and pushing publish, so only do it when asked
   to publish:

   ```sh
   git tag v<version> && git push origin v<version>
   ```

5. Watch the **Release** workflow for that tag with `gh run list`, `gh run view` and
   `gh run watch`. The `tests` job runs `test.yml` on the tagged commit and nothing else starts
   until it passes. A real failure there means fix the branch and move the unpublished tag, as
   `RELEASING.md` says, since a rerun tests the same commit; that run made no draft. The
   `changelog` job regenerates `CHANGELOG.md`, commits it as `chore(changelog): v<version>` to
   `release/<version>`, the line the tag was cut on, and creates the GitHub Release as a draft with
   the git-cliff notes. The `release` job builds, signs, notarises, attaches the DMG and ZIP,
   publishes the draft, and posts to Discord when that secret is set. If it fails, inspect the
   failed job before retrying and prefer `gh run rerun <run-id> --failed`. Do not delete or move a
   published tag. `workflow_dispatch` with a tag attaches the artefacts to a release that is still a
   draft and publishes it, not as Latest, without touching the changelog, so set Latest by hand when
   it is the newest stable tag. A published release is immutable and takes no new files.

6. Open the pull request from `release/<version>` into `main`, titled `Release <version>`. That is
   the one title the pull request title check accepts without a conventional prefix, and only from
   a `release/*` branch into `main`. It is merged with a merge commit, never squashed, so the tag
   stays reachable from `main`.

7. Merge `main` back into `develop` through a branch `chore/merge-back-v<version>`, with a pull
   request titled `chore(release): merge v<version> back into develop`, merged with a merge commit,
   so `develop` carries the tag and the changelog. Both merges are the owner's to make.

8. Verify the GitHub release notes and both assets. Installed copies update from the latest
   stable release and only accept `unified_dev_<version>_aarch64.zip` signed by the same team, so
   check that asset is there, and that `CHANGELOG.md` on `release/<version>` carries the new
   version. Report the release URL, the workflow result and the two pull requests.

## Package locally

`./Tools/release.sh [<ref>] [--tag <tag>] [--no-dmg]` (or `make release`) creates signed,
notarised artefacts in `dist/` from committed code. It needs a Developer ID signing identity and
notarisation credentials, and it publishes nothing. For an isolated app to test, use
`unifieddev-dev-build` instead.
