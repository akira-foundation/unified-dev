#!/bin/zsh
# Runs the Core test suite without building the SwiftUI app target.
#
# `swift test` on the real package always builds the Unified Dev executable too, so a single broken
# view stops every core test from running. This mirrors the core sources into a throwaway
# package that has no app target, which keeps the core suite runnable at all times.
#
#   ./Tools/test-core.sh                   run everything, which is also `make test`
#   ./Tools/test-core.sh DiffParser        run one suite by filter
#   ./Tools/test-core.sh DiffParser Git    run several (each argument is its own --filter)
#   UD_TEST_RUNS=5 ./Tools/test-core.sh run the whole thing five times, to shake out flakes
#
# Environment:
#   UD_TEST_ID       stable name for the work and build directories, so repeated runs by the
#                       same caller stay incremental
#   UD_TEST_RUNS     how many times to run the suite (default 1)
#   UD_LOCAL_AGENTS  =1 asserts which agent CLIs exist on this machine
#   UD_LOCAL_SETTINGS=1 parses the .conductor/settings.toml files on this machine
#   UD_SETTINGS_HOME is set by this script to an empty directory, so the home settings files
#                       the app reads are never this machine's
#   UD_LOCAL_SKILLS  =1 reads the commands, skills and plugins installed on this machine
#   UD_LOCAL_PROJECT names the checkout UD_LOCAL_SKILLS reads project commands out of. The
#                       suite runs from the mirror, so its own working directory is the wrong
#                       answer and there is nothing to default to
#   UD_LOCAL_TRANSCRIPTS =1 reads the agent transcripts on this machine, read only, and
#                    prints what the first build and a refresh cost over them
#   UD_LIVE          =1 drives the real `claude` binary. Costs money.
#   UD_TEST_SWIFT_ARGS  extra flags for `swift test`, split on spaces. For the runs that are
#                       not the ordinary one: the nightly workflow passes --sanitize=thread and
#                       --enable-code-coverage through here rather than reimplementing the
#                       mirrored package it needs to avoid building the app target.
#

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
TMP="${TMPDIR:-/tmp}"
ID="${UD_TEST_ID:-$$}"

# Read by the test suites themselves rather than by this script, so the legacy spelling has to be
# promoted into the environment the tests actually see.
# Per-invocation, because two of these running at once would otherwise share one build database
# and corrupt each other. The scratch path has to carry the same id: it *is* the build database,
# so leaving it shared would have re-introduced exactly the corruption the work directory avoids.
WORK="$TMP/unifieddev-core-tests-$ID"
SCRATCH="$TMP/unifieddev-core-build-$ID"

# **Both go when this exits, unless the caller named the run.** A build directory is ~750MB and
# this script made a fresh one per invocation and never removed it; on the machine this was written
# on that had reached **463 of them, 300GB**, and the disk filled during an ordinary afternoon of
# agents running the suite. Naming a run through UD_TEST_ID is the one case that wants the
# directory kept, because that is what makes a repeated run incremental, and a caller that named it
# is a caller that knows it is there.
#
# `EXIT` alone covers the ordinary end and a `set -e` failure; the signals are the ones a person or
# an editor sends, and without them a cancelled run keeps its 750MB for ever.
if [[ -z "${UD_TEST_ID:-}" ]]; then
  trap 'rm -rf "$WORK" "$SCRATCH"' EXIT INT TERM HUP
fi

# What a previous run left when it was killed outright, which no trap can cover. A day, so a run
# still going on somebody else's terminal is never swept out from under them, and quiet because
# this is tidying rather than news. The test process sweeps its own scratch the same way: see
# `TestProcessScratch` in Tests/CoreTests/TestSupport.swift.
find "$TMP" -maxdepth 1 \( -name 'unifieddev-core-build-*' -o -name 'unifieddev-core-tests-*' \
  -o -name 'unifieddev-test-run-*' -o -name 'unifieddev-browser-build-*' \
  -o -name 'unifieddev-browser-tests-*' \) -mtime +1 -print0 2>/dev/null \
  | xargs -0 -n 20 rm -rf 2>/dev/null || true

rm -rf "$WORK"
mkdir -p "$WORK/Sources" "$WORK/Tests"
ln -sfn "$ROOT/Sources/Core" "$WORK/Sources/Core"
# The MCP shim, mirrored alongside. It depends on Core and nothing else, so building it here
# cannot be stopped by a broken view, which is the whole reason this mirror exists. It is built
# rather than merely compiled because BridgeShimTests drives the real binary: a shim that is only
# ever spoken to by another test proves nothing about the process an agent CLI actually launches.
ln -sfn "$ROOT/Sources/bridge" "$WORK/Sources/bridge"
ln -sfn "$ROOT/Tests/CoreTests" "$WORK/Tests/CoreTests"
# The tests find a fixture by walking up from their own file, so it has to be reachable
# from the mirrored Tests directory as well as from the real one.
ln -sfn "$ROOT/Tests/fixtures" "$WORK/Tests/fixtures"

cat > "$WORK/Package.swift" <<'EOF'
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CoreOnly",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "Core", swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "bridge",
            dependencies: ["Core"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
EOF

filters=()
for name in "$@"; do
  filters+=(--filter "$name")
done

# Split on spaces, which is what ${=...} is for. An unset variable leaves an empty array, and an
# empty array in quotes expands to no words at all, so the ordinary run is unchanged.
extra=(${=UD_TEST_SWIFT_ARGS:-})

cd "$WORK"

export UD_LOGIN_SHELL_PATH=0

export UD_SETTINGS_HOME="$WORK/home"
mkdir -p "$UD_SETTINGS_HOME"

# The shim, built once and named in the environment, because `BridgeRegistration.shimPath` looks
# beside the running executable and the running executable here is the test bundle's. Failing to
# build it is fatal: `BridgeAskIdentityTests` registers a chat through the shim and would fail with
# a message about the registry rather than about the build.
if ! bridge_log="$(swift build --scratch-path "$SCRATCH" --product bridge 2>&1)"; then
  print -r -- "$bridge_log" | tail -n 40 >&2
  print -r -- "===> could not build bridge, and the suite cannot run without it" >&2
  exit 1
fi
export UD_BRIDGE_SHIM="$(swift build --scratch-path "$SCRATCH" --show-bin-path)/bridge"

runs="${UD_TEST_RUNS:-1}"
failed=0
for run in $(seq 1 "$runs"); do
  if [[ "$runs" -gt 1 ]]; then
    print -r -- "===> run $run of $runs"
  fi
  if ! swift test --scratch-path "$SCRATCH" "${extra[@]}" "${filters[@]}"; then
    failed=$((failed + 1))
  fi
done

if [[ "$failed" -gt 0 ]]; then
  print -r -- "===> $failed of $runs runs failed"
  exit 1
fi
