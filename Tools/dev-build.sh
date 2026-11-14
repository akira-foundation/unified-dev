#!/bin/zsh
# Builds the second Unified Dev, the one Unified Dev is developed in, and installs it to
# ~/Applications/Unified Dev (Dev).app, or with --preview this worktree's own preview app.
#
#   ./Tools/dev-build.sh              build HEAD, install, relaunch the dev copy
#   ./Tools/dev-build.sh <ref>        build that commit or branch instead
#   ./Tools/dev-build.sh --no-launch  install without restarting the dev copy
#   ./Tools/dev-build.sh --fast       debug build of current files, including uncommitted edits
#   ./Tools/dev-build.sh --fast --no-install  build only
#   ./Tools/dev-build.sh --preview    this worktree's own preview app, in .build/preview
#   ./Tools/dev-build.sh --label <text>  name the build in every window title
#
# `make dev` is the first of those.
#
# WHY A SECOND IDENTITY AND NOT A SECOND BUILD. Two copies of the same bundle id
# are the same app twice: same Application Support container, same preferences
# domain, same saved window state, same tmux sockets, same database. An agent
# clicking around in one of them archives the other one's workspaces. So this
# does not build a different Unified Dev, it builds Unified Dev AS SOMEBODY ELSE, and every
# separation macOS gives us follows from the bundle id:
#
#   io.akira.unifieddev.dev   its own `defaults` domain and its own saved window state
#   UD_DB_PATH         its own database, through LSEnvironment in Info.plist,
#                         which `Store.defaultPath` already honours, and, if that
#                         never arrives because the executable was run rather than
#                         opened, through the bundle id again: the fallback
#                         directory is derived from it. The tmux socket is derived
#                         from the database path, so that separates too, and so
#                         does the notification identifier
#   unifieddevdev:             its own URL scheme, so the dev copy cannot steal a
#                         `unifieddev://` deep link meant for the copy in daily use
#
# HOW IT IS TOLD APART, which matters more than any of the above because the
# failure is the owner typing into the wrong window:
#
#   the icon      a third of a turn round the colour wheel, so the same layers
#                 arrive on orange instead of violet. Tools/icon/dev-tint.py
#   the name      "Unified Dev (Dev)" in the Dock, in the Cmd-Tab switcher and as the
#                 first item of the menu bar
#   the title     every window title is prefixed "[DEV] ", or "[DEV · <label>] "
#
# HOW THE THREE MARKS ARE APPLIED. Not by committing a second Info.plist, a
# second icon and a branch in a view. They are applied to the detached worktree
# this builds from, so the repository has one identity and this script owns the
# second one entirely. The title is the one mark read at run time, from the
# UDWindowTitlePrefix key, so no Swift source is edited and a dev build
# compiles the same files as every other build.
#
# The rest is Tools/master.sh's shape and for its reasons: a detached worktree at
# a commit, because the working tree is mid edit at any moment and may not
# compile, and its own scratch path, because agents share `.build` and a build
# that races another agent's edits is a mixture of two states.

set -euo pipefail
cd "$(dirname "$0")/.."
source "$PWD/Tools/guard.sh"

REF=HEAD
REF_GIVEN=0
LAUNCH=1
INSTALL=1
FAST=0
CONFIG=release
BUILD_ARGS=(-r)
PREVIEW=0
LABEL=""
while (( $# )); do
  case "$1" in
    --no-launch) LAUNCH=0 ;;
    --no-install) INSTALL=0; LAUNCH=0 ;;
    --fast) FAST=1; CONFIG=debug; BUILD_ARGS=(--jobs 4) ;;
    --preview) PREVIEW=1; FAST=1; LAUNCH=0; CONFIG=debug; BUILD_ARGS=(--jobs 4) ;;
    --label)
      (( $# > 1 )) || { echo "--label needs a value" >&2; exit 1; }
      LABEL="$2"
      shift
      ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) REF="$1"; REF_GIVEN=1 ;;
  esac
  shift
done
IDENTITY=0
(( PREVIEW )) || [[ -n "$LABEL" ]] && IDENTITY=1

if (( FAST && REF_GIVEN )); then
  echo "--fast builds current files and cannot be combined with a revision" >&2
  exit 1
fi

RESOLVED="$(git rev-parse --short "$REF")"
BRANCH="$(git branch --show-current)"
SUBJECT="$(git log -1 --format=%s "$REF")"
WORK=/tmp/unifieddev-dev-src
DEST="$UD_DEV_APP"
(( PREVIEW )) && DEST="$PWD/.build/preview"

BUILD_LOCK="$(git rev-parse --path-format=absolute --git-common-dir)"
BUILD_LOCK="${BUILD_LOCK:h}/.claude/preview.lock"
BUILD_LOCK_HELD=0

take_build_lock() {
  local holder pid announced=0
  mkdir -p "${BUILD_LOCK:h}"
  while ! ( setopt noclobber; print -r -- "pid=$$ slug=${PWD:t} branch=$BRANCH started=$(date +%H:%M:%S)" >"$BUILD_LOCK" ) 2>/dev/null; do
    holder="$(cat "$BUILD_LOCK" 2>/dev/null || true)"
    pid="$(print -r -- "$holder" | sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p')"
    if [[ -z "$pid" && -n "$holder" ]]; then
      print -ru2 -- "==> $BUILD_LOCK is held by a reservation written by hand:"
      print -ru2 -- "    $holder"
      print -ru2 -- "    Remove it once that preview is done, then run this again."
      exit 1
    fi
    if [[ -n "$pid" ]] && ! kill -0 "$pid" 2>/dev/null; then
      if mv "$BUILD_LOCK" "$BUILD_LOCK.$$" 2>/dev/null; then
        if [[ "$(cat "$BUILD_LOCK.$$" 2>/dev/null)" == "$holder" ]]; then
          rm -f "$BUILD_LOCK.$$"
        else
          mv -n "$BUILD_LOCK.$$" "$BUILD_LOCK" 2>/dev/null || rm -f "$BUILD_LOCK.$$"
        fi
      fi
      continue
    fi
    if (( ! announced )); then
      echo "==> waiting for another build to finish: $holder"
      announced=1
    fi
    sleep 5
  done
  BUILD_LOCK_HELD=1
}

release_build_lock() {
  (( BUILD_LOCK_HELD )) || return 0
  if [[ "$(cat "$BUILD_LOCK" 2>/dev/null)" == "pid=$$ "* ]]; then
    rm -f "$BUILD_LOCK"
  fi
  BUILD_LOCK_HELD=0
}

# This script has the same shape as Tools/master.sh and therefore the same
# hazard: an agent running inside the DEV copy would have this replace and kill
# its own host. The second line is belt and braces against a typo or a stale
# environment ever pointing DEST at the copy the owner is using.
if (( INSTALL && ! PREVIEW )); then
  ud_refuse_if_own_host "$DEST" "$UD_DEV_DB"
fi
ud_refuse_real_app "$DEST"

echo "==> $RESOLVED  $SUBJECT"

take_build_lock
trap 'release_build_lock' EXIT

if (( FAST )); then
  FAST_ROOT="/tmp/unifieddev-dev-fast-$(printf '%s' "$PWD" | shasum | cut -c1-12)"
  mkdir -p "$FAST_ROOT"
  if ! mkdir "$FAST_ROOT/lock" 2>/dev/null; then
    echo "Another fast build is running. If it stopped unexpectedly, remove $FAST_ROOT/lock." >&2
    exit 1
  fi
  WORK="$(mktemp -d "$FAST_ROOT/stage.XXXXXX")"
  trap 'release_build_lock; rm -rf "$WORK"; rmdir "$FAST_ROOT/lock"' EXIT
  python3 - "$WORK" <<'COPY'
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(sys.argv[1])
files = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard'])
for name in set(files.split(b'\0')) - {b''}:
    source = Path(os.fsdecode(name))
    if not source.is_file() and not source.is_symlink():
        continue
    target = root / source
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target, follow_symlinks=False)
COPY
  RESOLVED="$RESOLVED-working"
  echo "==> debug build of current files (including uncommitted edits)"
else
  git worktree remove --force "$WORK" 2>/dev/null || true
  rm -rf "$WORK"
  git worktree add --detach "$WORK" "$RESOLVED" >/dev/null
  if [[ ! -f "$WORK/Sources/Core/Presentation/WindowTitleMark.swift" ]]; then
    git worktree remove --force "$WORK" 2>/dev/null || true
    print -ru2 -- "==> $RESOLVED predates the title mark read from UDWindowTitlePrefix, so a dev build of it"
    print -ru2 -- "    would look exactly like the real app. Build a revision from after that change."
    exit 1
  fi
fi

# ---------------------------------------------------------------- the identity

PLIST="$WORK/Resources/Info.plist"
# The redirect hides the value PlistBuddy echoes back and nothing else: it
# reports a missing key or a malformed command on stderr and exits 1, so a
# mistyped key path still stops the build under `set -e`. Measured, because a
# silent identity edit is how a dev build ends up wearing the real name.
plist() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" >/dev/null; }

plist "Set :CFBundleName Unified Dev (Dev)"
plist "Set :CFBundleDisplayName Unified Dev (Dev)"
plist "Set :CFBundleIdentifier $UD_DEV_BUNDLE_ID"
plist "Set :CFBundleURLTypes:0:CFBundleURLName $UD_DEV_BUNDLE_ID.deeplink"
plist "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 unifieddevdev"
plist "Set :NSServices:0:NSPortName Unified Dev (Dev)"
plist "Set :NSServices:0:NSMenuItem:default New Unified Dev (Dev) Workspace"

# The database, and the only reason the dev copy is safe to click around in.
#
# LSEnvironment is a real dictionary of environment variables that LaunchServices
# puts into the process it starts, so `Store.defaultPath` finds UD_DB_PATH in
# `ProcessInfo.processInfo.environment` exactly as it would from a shell. It has
# to be an absolute path: LSEnvironment expands nothing, so `$HOME` is resolved
# here and baked in.
#
# It is applied by LaunchServices, which means it applies when the app is opened
# and not when its executable is run directly. Open the dev copy with `open` or
# from the Dock. A build launched as ~/Applications/Unified Dev (Dev).app/Contents/MacOS/UnifiedDev
# has no UD_DB_PATH at all. That used to be the one way to defeat all of this,
# and it is not any more: `Store.databaseDirectoryName` derives the fallback
# directory from the bundle id, and io.akira.unifieddev.dev resolves to this same
# "Unified Dev (Dev)" directory rather than to the real one. So this key is belt now, not
# the only strap, and the two have to agree on the path. The check at the foot of
# this script reads the value back out of the launched process rather than
# assuming it arrived.
#
# The delete is the one call here allowed to fail, because Resources/Info.plist
# does not carry an LSEnvironment and PlistBuddy treats deleting an absent key as
# an error. The two Adds under it are not allowed to fail, and do not.
plist "Delete :LSEnvironment" 2>/dev/null || true
plist "Add :LSEnvironment dict"
plist "Add :LSEnvironment:UD_DB_PATH string $UD_DEV_DB"
plutil -replace UDWindowTitlePrefix -string "[DEV] " "$PLIST"

# The icon, recoloured in place in the worktree. Same document, same layer names,
# same CFBundleIconName, so Tools/build.sh compiles it with actool unchanged.
python3 Tools/icon/dev-tint.py "$WORK/Resources/UnifiedDev.icon/icon.json"

# ------------------------------------------------------------------- the build

# The worktree's `.build` is a symlink into a scratch directory that outlives it.
#
# Two things at once. The worktree is thrown away and recut on every run, so
# without this every dev build is a cold release build of the whole package,
# which is minutes; through the symlink Swift Package Manager sees the same paths
# it saw last time and rebuilds what changed. And the scratch is still this
# script's alone, so a concurrent agent build cannot swap objects underneath it,
# which is the reason Tools/master.sh takes a scratch path of its own.
if (( FAST )); then
  # Apply identity edits before syncing so unchanged Swift files keep their timestamps.
  mkdir -p "$FAST_ROOT/src" "$FAST_ROOT/build"
  rsync -a --no-times --checksum --delete --exclude=.build "$WORK/" "$FAST_ROOT/src/"
  rm -rf "$WORK"
  WORK="$FAST_ROOT/src"
  trap 'release_build_lock; rmdir "$FAST_ROOT/lock"' EXIT
  ln -sfn "$FAST_ROOT/build" "$WORK/.build"
else
  mkdir -p /tmp/unifieddev-dev-build
  ln -sfn /tmp/unifieddev-dev-build "$WORK/.build"
fi

# The bundle the last run left in that scratch, removed before this one starts.
#
# The scratch outliving the worktree is what makes a rebuild take seconds, and it
# is also the one way this script could install something it never built.
# Tools/build.sh assembles the bundle at .build/release/UnifiedDev.app, and a build
# that fails before it reaches that step leaves the previous run's bundle sitting
# at exactly the path the copy below reads. Nothing downstream can tell a bundle
# from twenty minutes ago apart from a fresh one: same path, same name, same
# shape. So the old one goes first, and the only bundle that can be installed is
# one this run produced.
rm -rf "$WORK/.build/$CONFIG/UnifiedDev.app"

# The build, kept quiet when it works and printed in full when it does not.
#
# This line used to end in `>/dev/null`, and `swift build` writes compiler errors
# to STDOUT rather than to stderr, so that redirect threw away the only account
# of what had gone wrong. The script still stopped, `set -e` sees a failing
# subshell perfectly well, but it stopped after forty seconds with four lines of
# output and no mention of the error, which is worse than a noisy failure: the
# next person reads it as the script being broken rather than the code.
#
# Kept in a file rather than left on the terminal, because a build that works is
# a page of module names nobody reads. Printed WHOLE rather than tailed, because
# a tail is the same mistake in smaller print: Swift reports the first error at
# the top and then keeps compiling, so the line that explains the failure is not
# reliably in the last forty.
BUILD_LOG=/tmp/unifieddev-dev-build.log
(( FAST )) && BUILD_LOG="$FAST_ROOT/build.log"
if ! ( cd "$WORK" && ./Tools/build.sh "${BUILD_ARGS[@]}" && { (( ! IDENTITY )) || swift build -c "$CONFIG" "${BUILD_ARGS[@]}" --product preview; } ) >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG" >&2
  print -ru2 -- ""
  print -ru2 -- "==> the dev build failed. The whole log is above, and in $BUILD_LOG."
  print -ru2 -- "    Nothing was installed, so $DEST is whatever it was before."
  exit 1
fi

BUILT="$WORK/.build/$CONFIG/UnifiedDev.app"
[ -d "$BUILT" ] || BUILT="$(cd "$WORK" && swift build -c "$CONFIG" --show-bin-path)/UnifiedDev.app"
BUILT="${BUILT:A}"

# Belt and braces on the removal above. A build that reports success without
# leaving a bundle behind must not reach the copy below, because the only thing
# there would be to copy is whatever somebody else put there.
if [[ ! -d "$BUILT" ]]; then
  print -ru2 -- "==> the build reported success but left no bundle at $BUILT"
  exit 1
fi

# What this is, so a stale install can be identified without guessing. The same
# key Tools/master.sh writes, plus one that says which of the two this is.
#
# These used to end in `|| true`, which is the wrong trade for the one pair of
# keys anybody reads when they are already confused about which build they are
# looking at. If the stamp cannot be written the bundle is unidentifiable, and
# that is worth stopping for.
(( FAST )) && release_build_lock

if (( IDENTITY )); then
  IDENTITY_FILE="$(mktemp -t unifieddev-identity)"
  "$(cd "$WORK" && swift build -c "$CONFIG" --show-bin-path)/preview" identity \
    --worktree "$PWD" --branch "$BRANCH" --label "$LABEL" >"$IDENTITY_FILE"
  ud_read_preview_identity "$IDENTITY_FILE"
  plutil -replace UDWindowTitlePrefix -string "${UD_PREVIEW[title_prefix]}" "$BUILT/Contents/Info.plist"
fi

if (( PREVIEW )); then
  ud_refuse_unless_preview "$PWD"
  if ! claim="$("$(cd "$WORK" && swift build -c "$CONFIG" --show-bin-path)/preview" claim \
    --worktree "$PWD" --branch "$BRANCH" --label "$LABEL" 2>&1)"; then
    print -ru2 -- "==> $claim"
    exit 1
  fi
  DEST="${UD_PREVIEW[app_path]}"
  ud_refuse_if_own_host "$DEST" "${UD_PREVIEW[database]}"
  /usr/bin/python3 Tools/preview-plist.py "$BUILT/Contents/Info.plist" "$IDENTITY_FILE"
fi

/usr/bin/defaults write "$BUILT/Contents/Info.plist" MasterCommit -string "$RESOLVED"
/usr/bin/defaults write "$BUILT/Contents/Info.plist" UnifiedDevDevBuild -bool true

# Re-signed, because the two writes above invalidated the signature Tools/build.sh
# applied. Same identity resolution as that script, so a machine with a real one
# configured keeps it and everything else stays ad-hoc.
#
# Not `|| true`, unlike the equivalent line in Tools/build.sh. There the bundle
# has never been signed and an unsigned one still launches, so a failure costs
# only App Intents. Here the signature was valid until the two writes above broke
# it, and macOS kills a bundle whose signature no longer matches its contents. A
# swallowed failure would surface three steps down as "launched, but no process
# is running from ...", which is true and says nothing about the cause.
if ! signing="$(codesign --force --deep --sign "${UD_CODESIGN_IDENTITY:-${BATON_CODESIGN_IDENTITY:--}}" "$BUILT" 2>&1)"; then
  print -ru2 -- "$signing"
  print -ru2 -- "==> re-signing $BUILT failed, so it would not launch."
  print -ru2 -- "    Nothing was installed; fix the signing identity and run this again."
  exit 1
fi

if (( ! INSTALL )); then
  echo "==> built $BUILT"
  echo "==> nothing installed or launched"
  if (( ! FAST )); then
    git worktree remove --force "$WORK" 2>/dev/null || true
  fi
  exit 0
fi

if (( PREVIEW )); then
  if [[ -n "$(ud_app_pids "$DEST")" ]]; then
    print -ru2 -- "==> ${UD_PREVIEW[app_name]} is open. Quit it, then run this again; nothing was installed."
    exit 1
  fi
  mkdir -p "${UD_PREVIEW[root]}"
  rm -rf "$DEST"
  cp -R "$BUILT" "$DEST"
  cp "$IDENTITY_FILE" "${UD_PREVIEW[root]}/identity.env"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$DEST" >/dev/null 2>&1 || true
  echo "==> installed $DEST"
  echo "==> database ${UD_PREVIEW[database]}"
  echo "==> open it with:"
  print -r -- "    open \"$DEST\" --args --scenario <absolute path to a scenario.json>"
  exit 0
fi

mkdir -p "$HOME/Applications"
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

# LaunchServices caches Info.plist per bundle, LSEnvironment included, so a
# rebuild that changed it is not seen until the bundle is registered again.
#
# Best effort on purpose, and the only redirect here that hides a failure. A
# refused registration leaves a stale LSEnvironment, which is caught by the check
# at the foot of this script rather than being trusted, and lsregister has no
# useful exit status to act on anyway.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$DEST" >/dev/null 2>&1 || true

if (( ! FAST )); then
  git worktree remove --force "$WORK" 2>/dev/null || true
fi

echo "==> installed $DEST"
echo "==> database $UD_DEV_DB"

if [ "$LAUNCH" -eq 1 ]; then
  # By pid, and only pids of the dev bundle. The real copy is a different
  # executable path, so it is never a candidate. No pattern kill anywhere near
  # this: `pkill -f Unified Dev` would take the owner's app with it.
  for pid in $(ud_app_pids "$DEST"); do
    kill "$pid" 2>/dev/null || true
  done
  sleep 1
  open "$DEST"
  sleep 3

  # Nothing above proves the dev copy is on its own database. `ps -E` prints the
  # environment of a process this user owns, which is the only honest answer:
  # LaunchServices could have served a cached Info.plist, or somebody could have
  # started the executable directly. A dev copy silently running against the real
  # database is the failure this whole file exists to prevent, so it is checked.
  running="$(ud_app_pids "$DEST" | head -1)"
  if [[ -z "$running" ]]; then
    echo "==> launched, but no process is running from $DEST" >&2
    exit 1
  fi
  if ps -E -p "$running" 2>/dev/null | grep -q "UD_DB_PATH=$UD_DEV_DB"; then
    echo "==> launched pid $running, on its own database"
  else
    # Not "on the REAL database" any more: with no UD_DB_PATH, Store derives the directory
    # from the dev bundle id and lands on Unified Dev (Dev) anyway. But a missing key means
    # LaunchServices served a stale plist or the executable was run by hand, and this build is
    # down to one mechanism where two agreeing ones are the point, so it still stops.
    echo "==> pid $running has no UD_DB_PATH. The bundle id fallback is holding the" >&2
    echo "    separation alone. Quit it, then start it again with: open \"$DEST\"" >&2
    exit 1
  fi
fi
