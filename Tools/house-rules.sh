#!/bin/bash
# The conventions this repository has that no off the shelf linter knows about.
#
#   ./Tools/house-rules.sh
#
# The first ten rules, and most of them are here because they have already been
# broken (rule 9 says it is the exception). Later rules are described where they
# are defined, under their own echo line:
#
#   1. No em dashes and no en dashes. Anywhere. They arrive by the hundred from
#      anything that writes prose for you, and once one is in a file the next
#      writer copies the house style it thinks it sees.
#   2. The app is Unified Dev. It was called Baton until it was renamed, and the old
#      name still turns up in new text written from stale memory.
#   3. British spelling. The tree is already at 69 greys to 1 gray and 74
#      cancelleds to 1 canceled, so this is about keeping it that way.
#   4. Only the app target imports a UI framework. CLAUDE.md has said so since
#      the split was made and nothing checked it, which is the state every rule
#      here was in the day before it was written.
#   5. One way to start a workspace. Four routes each grew their own half of it
#      once already; see the rule itself for what that cost.
#   6. One way to move a state. The three columns that describe what a workspace
#      or a chat IS are only movable through the lifecycle that also does the
#      work the move implies; see the rule itself.
#   7. An id has a type. Every id was a bare String until they were not, and a
#      new one declared that way puts the hole back without the compiler having
#      anything to say about it.
#   8. A View does not run a subprocess. A decision taken inside a View is a
#      decision nothing can test, and CLAUDE.md said so for weeks while nothing
#      checked it; see the rule itself for the helper types that are the way out.
#   9. A catch says something. This one is here before it has been broken, which
#      makes it the exception, and it is here because SwiftLint cannot hold it:
#      its `custom_rules` need SourceKit, there is none on Linux, and the lint
#      job skips them and stays green. See the rule itself.
#  10. No subprocess is rooted at the home directory. Four were, three of them as
#      a default argument nobody read, and macOS blames Unified Dev for whatever the
#      child then touches; see the rule itself.
#
# Exit status is 1 if anything was found, and every finding is printed with the
# file and line so it can be opened. The word lists are deliberately narrow:
# a rule that cries wolf gets switched off, so anything with a legitimate use in
# this codebase either stays out of the list or is named in an exception below.
#
# **Every search here passes `--untracked`, and that is load bearing.** Six of the
# eight rules that existed then did not, and a plain `git grep` sees only what is
# tracked, so a brand new file was invisible to all six until somebody staged it.
# One decoy file inside `Sources/Core` carrying a violation of each raised
# one finding untracked and six the moment it was added, on identical bytes. That
# is worst exactly where it matters: rules 4, 5 and 6 say in their own comments
# that the compiler holds everything EXCEPT a new file inside the core, and a new
# file is untracked until it is staged, so `make lint` passed on precisely the
# thing the rule exists to catch. `--untracked` does not include ignored files,
# so `.build` and the rest of .gitignore stay out.

set -euo pipefail
cd "$(dirname "$0")/.."

findings=0

report() {
  findings=$((findings + 1))
  echo "$1"
}

# One line per hit, cut short. A recorded fixture is one line of several
# kilobytes, and the file and line number are the part you need anyway.
show() {
  while IFS= read -r line; do echo "  ${line:0:160}"; done
}

# The two characters this file is not allowed to contain, since it is scanned by
# the rule it implements. Built from their UTF-8 bytes instead.
em_dash="$(printf '\342\200\224')"
en_dash="$(printf '\342\200\223')"

echo "==> no em dashes or en dashes"
# .claude holds agent skills written elsewhere and vendored in as they are, and
# the fixtures hold recorded sessions that have to stay byte for byte what the
# agent actually emitted. Neither is house prose and neither may be rewritten.
# The fixtures are matched wherever they sit, because they are being moved.
if hits="$(git grep --untracked -n -I -e "$em_dash" -e "$en_dash" -- ':!.claude' ':!*fixtures/*' || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "A dash that should be a comma, a full stop or a pair of brackets."
fi

echo "==> the app is called Unified Dev"
# This file is exempt from this rule and the spelling rule below, because it has
# to spell out what it is looking for. The dash rule above does apply to it,
# which is why those two characters are built from their bytes rather than typed.
#
# Every file that is allowed to say Baton, and why. This list should only ever
# get shorter. A file not on it that mentions the old name is a new mistake.
baton_allowed=(
  '*PROTOCOL.md'                                    # quotes a recorded session
  '*build.sh'                                       # BATON_CODESIGN_IDENTITY, kept working on purpose
  '*fixtures/'                                      # recorded sessions, byte for byte
  'Sources/Core/Persistence/LegacyDatabase.swift'          # reads the old app's database
  'Sources/Core/Persistence/LegacyDefaults.swift'          # reads the old app's preferences
  'Sources/Core/Workspace/WorkspaceManager.swift'        # a comment about the old worktree home
  'Tests/CoreTests/AgentEventTests.swift'      # sample paths and recorded payloads
  'Tests/CoreTests/FilePathGuessTests.swift'   # sample paths
  'Tests/CoreTests/HomeListTests.swift'        # a sample repository name
  'Tests/CoreTests/LegacyMigrationTests.swift' # tests the migration off the old name
  'Tests/CoreTests/RepositoryStartPlanTests.swift' # sample folder names
)
for file in $(git grep --untracked -l -I -i baton -- ':!.claude' ':!Tools/house-rules.sh' || true); do
  allowed=0
  for prefix in "${baton_allowed[@]}"; do
    # Unquoted on purpose, so an entry can be a pattern. A file is being moved
    # under this list's feet and none of these paths contain a space.
    # shellcheck disable=SC2254
    case "$file" in $prefix*) allowed=1 ;; esac
  done
  if [ "$allowed" -eq 0 ]; then
    git grep --untracked -n -I -i baton -- "$file" | show
    report "$file calls the app by its old name."
  fi
done
# Not a finding, just housekeeping: an exception nobody needs any more.
for prefix in "${baton_allowed[@]}"; do
  case "$prefix" in */|*'*'*) continue ;; esac
  if [ -f "$prefix" ] && ! git grep --untracked -q -I -i baton -- "$prefix"; then
    echo "  note: $prefix no longer says Baton, so it can come off the list in $0."
  fi
done

echo "==> only the app target imports a UI framework"
# The split only means anything while it holds. Everything in Core is
# reachable by the test target and everything in Sources/UnifiedDev is not, so a
# decision that drifts into a view is a decision nothing can test. One import is
# how that starts. `bridge` is scanned for the same reason and one more: it
# is a stdio relay a CLI launches as a child process, and it has no user
# interface to put a window in.
#
# Two spellings got past the two literals this used to look for, and both were
# compiled to check rather than reasoned about. `import Cocoa` brings NSView in
# by re-export, so a core file could have the whole of AppKit without naming it.
# `import class AppKit.NSView` names AppKit and does not contain the string
# "import AppKit", because the declaration kind sits between the two words. So
# this matches the framework after `import` and an optional declaration kind,
# whatever is in front of them, which also covers `@_exported import AppKit` and
# `@preconcurrency import SwiftUI`.
#
# SwiftTerm is in the same sentence in CLAUDE.md and deliberately
# not here. Only the app target declares it in `Package.swift`, so an import
# of it from the core or the bridge is a link error rather than a lint
# finding, and a rule that can never fire is a rule that gets believed in.
#
# WebKit is here, and was not until `Tests/BrowserScriptTests` was written. It
# is a system framework, so an `import WebKit` inside the core would have
# compiled and linked and this rule would have said nothing, while three places
# in the tree asserted that a target touching WebKit could not be in the
# package `Tools/test-core.sh` writes. That was true of the decision and not of
# the check.
#
# Only `Sources/*`, and that is the scope rather than an oversight. What the
# rule protects is in its own first paragraph: everything in the core is
# reachable by a test and everything in a view is not. A test target is on the
# reachable side by definition, and `Tests/BrowserScriptTests` imports WebKit
# because the only thing that can say what our injected JavaScript does to a
# page is a page. Widening these paths to `Tests/*` would break it, which is
# why the reason is written here rather than left to be rediscovered.
# Charts is here for the reason WebKit is: a system framework imported in the
# core would compile and link, and what a chart says would stop being testable.
ui_import='(^|[^A-Za-z0-9_])import[[:space:]]+([a-z]+[[:space:]]+)?(SwiftUI|AppKit|Cocoa|WebKit|Charts)([^A-Za-z0-9_]|$)'
if hits="$(git grep --untracked -n -I -E "$ui_import" -- 'Sources/Core/*' 'Sources/bridge/*' 'Sources/preview/*' || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "A target that is not Sources/UnifiedDev imports a UI framework. Move the view part into Sources/UnifiedDev and leave the decision behind, where the suite can reach it."
fi

echo "==> one way to start a workspace"
# `WorkspaceManager.createWorkspace` cuts a worktree and writes a row. It does
# not open the chat, write the model and effort onto it, run the setup script,
# name the workspace or record who asked for it. All of that is
# `WorkspaceManager.start`, and it is one method because it used to be four
# half-copies: the create sheet had the lot, the `unifieddev://` link and the
# Services menu had none of it and were silently hardwired to the defaults, and
# the Shortcuts intent could not reach any of it, so it fired a URL and then
# read the database every 400ms for a minute hoping to recognise its own row.
#
# The compiler holds most of this line, because `createWorkspace` is internal to
# Core and the app target cannot call it at all. What is left is a new file
# inside the core, which the compiler would allow and which is exactly how the
# next half-copy would start.
#
# The obvious way to delete this rule is to move `start` in beside
# `createWorkspace` and mark that `private`, since Swift's `private` is file
# scoped and the whole rule would become a compile error. It has been tried and
# it does not work, so it is written down here rather than proposed again.
# `@testable` raises `internal` to visible and leaves `private` alone, measured
# on a two module spike: "'createWorkspace' is inaccessible due to 'private'
# protection level". Eleven test suites reach the method directly across 29 call
# sites, and the paragraph below blesses exactly that, because a test that wants
# a worktree and nothing else must not have to open a chat, run a setup script
# and wake the naming model to get one. Making it `private` would take it from
# them as well as from the next half-copy. The 723 line file the merge would make
# is the smaller half of the cost.
#
# Every file inside the core allowed to name it, and why. This list should only
# ever get shorter. A file not on it that names it is a new mistake.
#
# The suite is not on it and does not need to be: it reaches the method through
# `@testable`, and a test that wants a worktree and nothing else is not a route
# into the app.
create_workspace_allowed=(
  'Sources/Core/Workspace/WorkspaceManager.swift' # declares it
  'Sources/Core/Workspace/WorkspaceStart.swift'   # the one caller: `start`
)
for file in $(git grep --untracked -l -I -e 'createWorkspace(' -- 'Sources/Core/*' || true); do
  allowed=0
  for path in "${create_workspace_allowed[@]}"; do
    [ "$file" = "$path" ] && allowed=1
  done
  if [ "$allowed" -eq 0 ]; then
    git grep --untracked -n -I -e 'createWorkspace(' -- "$file" | show
    report "$file cuts a worktree itself instead of calling WorkspaceManager.start. A route that stops at createWorkspace gets no chat, no setup run, no name and no record of who asked, and nothing says so."
  fi
done

echo "==> a state moves through its lifecycle"
# `Workspace.state`, `Workspace.setupState` and `Session.state` say what a thing
# IS, and setting one of them is never the whole of changing it. Archiving is
# removing the worktree and then saying so; a row that said a workspace was live
# after its worktree had gone is in CLAUDE.md and it does not heal. Filing a
# setup run is writing the state and the log together; `.failed` with nothing to
# read is a half-truth the next reader treats as whole, and a restored workspace
# went on saying `succeeded` about a directory deleted months earlier. So each of
# those three columns has one owner that takes an EVENT and does the whole job:
# `SetupLifecycle`, `SessionLifecycle`, `WorkspaceLifecycle`.
#
# The compiler holds most of this line. All three are `public internal(set)`, so
# nothing in `Sources/UnifiedDev` can assign one at all, however it reaches the value:
# through `Store.update`'s closure, through a copy of a row, anywhere. Nor can it
# go round the property and fabricate the value instead: the initialisers that
# name those columns are internal as well, so the one-line version of this (build
# a `Workspace` with an existing id and any state you like, hand it to the public
# `Store.upsert`, which writes every column) does not compile either. What is left
# is a new file inside the core, which the compiler would allow and which is
# exactly how a fourth writer would start, so that is all this looks at.
#
# It matches an assignment of a NAMED case, which is how a half-done transition
# is actually written, with or without a receiver in front of it: a new file
# extending `Workspace` can write `setupState = .succeeded` with no dot at all.
# Carrying a state the lifecycle already produced from one copy of a row to
# another (`$0.state = session.state` in the two runners) is not that and is not
# matched: those two lines mirror a value the table decided.
#
# Every file inside the core allowed to name one, and why. This list should only
# ever get shorter. A file not on it that names one is a new mistake.
#
# The suite is not on it and does not need to be: `@testable` reaches these, and
# a fixture stating what a row looked like is not a route into the app.
# One entry, and the other two lifecycles are absent because they do not need to
# be: `SetupLifecycle` and `SessionLifecycle` write the destination the table
# handed them rather than a case they named, so there is nothing here for this to
# see. If one of them ever starts naming a case, that is worth reading before it
# is worth allowing.
state_move_allowed=(
  'Sources/Core/Workspace/WorkspaceLifecycle.swift' # archive() and restore(), which name both
)
state_move='(^|[^A-Za-z0-9_])(state|setupState) *= *\.(active|archived|pending|running|succeeded|failed|ignored|skipped|idle|waiting|cancelled)([^A-Za-z0-9_]|$)'
for file in $(git grep --untracked -l -I -E "$state_move" -- 'Sources/Core/*' || true); do
  allowed=0
  for path in "${state_move_allowed[@]}"; do
    [ "$file" = "$path" ] && allowed=1
  done
  if [ "$allowed" -eq 0 ]; then
    git grep --untracked -n -I -E "$state_move" -- "$file" | show
    report "$file sets a lifecycle state directly instead of applying an event. A state written on its own is a state without the work that makes it true: an archive that removed nothing, or an outcome with no log under it. Use apply(), archive() or restore()."
  fi
done
# Not a finding, just housekeeping: an exception nobody needs any more.
for path in "${state_move_allowed[@]}"; do
  if [ -f "$path" ] && ! git grep --untracked -q -I -E "$state_move" -- "$path"; then
    echo "  note: $path no longer moves a state, so it can come off the list in $0."
  fi
done

echo "==> an id has a type"
# Every id in Unified Dev used to be a bare `String`, so `store.update(workspaceID:
# session.id)` compiled, ran, and updated no row at all. There is no crash and
# no log line for that, just a workspace that did not archive. The typed ids in
# Sources/Core/Model/Identifier.swift are what stopped it, eight of them as
# this is written, and the compiler holds the line everywhere they are used.
# They are not listed here on purpose: a list that reads as complete and is not
# is what makes the next reader think their new id is already covered.
#
# What the compiler cannot object to is a NEW property declared `var
# somethingID: String`, because a String is a perfectly good String. That one
# declaration reopens the hole quietly, and everything downstream of it goes
# back to being interchangeable. So this rule is about declarations, not usage:
# usage is already unrepresentable and needs no rule.
#
# Only stored properties are looked at. A computed `var id: String { path }` is
# an `Identifiable` conformance derived from something else and identifies no
# row, which is why `ChangedFileTree`, `SlashCommand` and a dozen others are not
# in the lists below and do not need to be.
#
# Two vocabularies are exempt wholesale, and both for the same reason: they are
# not Unified Dev's words. `AgentEvent` is Claude Code's stream-json and `CodexEvent`
# is the Codex app-server protocol, and every id in them (`uuid`, `toolUseID`,
# `threadID`, the CLI's own `sessionID`) is an opaque token Unified Dev receives,
# stores and hands back without ever looking inside. Typing those would mean a
# wrapper at every parse site and would buy nothing, because there is no second
# kind of thread id to confuse one with.
id_type_allowed_files=(
  'Sources/Core/Agent/AgentQuestion.swift' # Codex's opaque question answer id, not a Unified Dev row
  'Sources/Core/Agent/AgentEvent.swift'   # Claude Code's stream-json, as measured
  'Sources/Core/Agent/Codex/CodexEvent.swift'   # the Codex app-server protocol
  'Sources/Core/Agent/Codex/CodexTurnHandle.swift' # turn ids assigned by that server
  'Sources/Core/Agent/Codex/CodexClient.swift'  # the same protocol's request envelopes
  'Sources/Core/Agent/Grok/GrokEvent.swift'     # Grok's ACP session and tool-call ids
  'Sources/Core/Agent/Grok/GrokClient.swift'    # the same protocol's request envelopes
  'Sources/Core/Agent/Grok/GrokRunner.swift'    # Grok session ids assigned by that server
  'Sources/Core/Agent/AgentRetry.swift'   # the same stream-json, one line of it
)
# Names that are never a Unified Dev row, wherever they appear. This list should only
# ever get shorter. A name not on it is a new mistake.
id_type_allowed_names=(
  agentSessionID    # the CLI's session, not Unified Dev's. Different value, different lifetime
  spawnToolUseID    # a tool_use id out of a payload
  toolUseID         # the same
  parentToolUseID   # the same
  refID             # a stored tool_use id, so a result can find its call
  requestID         # the CLI's permission request
  messageID         # the CLI's message
  uuid              # the CLI's row identity
  threadID          # Codex's thread
  turnID            # Codex's turn
  itemID            # Codex's item
  clientID          # Codex's client
  processID         # a pid, as text
  bundleID          # macOS, not Unified Dev
  ownerID           # a split pane, which is the layout's namespace and not a row
)
# The remaining stored `String` ids, each one a deliberate decision. This list
# should only ever get shorter.
id_type_allowed_lines=(
  'Sources/Core/Presentation/HomeList.swift'                  # a date bucket key, not a row
  'Sources/Core/Presentation/ChatFontCatalogue.swift'          # a font family, which macOS names
  'Sources/Core/Persistence/Settings.swift'                  # a run script named in settings
  'Sources/Core/Agent/Codex/CodexModelCatalog.swift'         # a model name the CLI offers
  'Sources/Core/Agent/Grok/GrokModelCatalog.swift'           # a model name the CLI offers
  'Sources/Core/Agent/AgentModel.swift'                      # model and effort names the CLIs offer
  'Sources/Core/Presentation/ComposerEffort.swift'           # the same effort names, and the empty one that means none
  'Sources/Core/System/EditorCatalog.swift'             # an application, by bundle id
  'Sources/UnifiedDev/Views/Center/Composer/ComposerOption.swift'   # a picker entry, "opus" and friends
  'Sources/UnifiedDev/Views/Center/Panes/CenterTab.swift'       # a tab: a terminal row, a browser or the review pane
  'Sources/Core/System/TerminalPaneCensus.swift'        # the same tab id, read back off the same bytes
  'Sources/UnifiedDev/Views/Center/Attachments/PromptAttachment.swift' # a draft key, which has no session yet
  'Sources/UnifiedDev/State/TranscriptModel.swift'         # payload ids, read straight off an event
  'Sources/Core/GitHub/CheckFailureHandoff.swift'       # a GitHub Actions run and job, read out of a URL gh gave us
  'Sources/Core/Presentation/SearchPanelListing.swift'  # a section heading key, not a row
)
# External tokens carried beside typed Unified Dev ids. Limit each exemption to its
# property so adding another bare internal id in the same file still fails.
id_type_allowed_properties=(
  'Sources/Core/Agent/Delivery.swift:providerTurnID'             # the provider's accepted turn, used for recovery
  'Sources/Core/Transcript/TurnCheckpoint.swift:providerTurnID' # the same provider turn correlated with a snapshot
  'Sources/Core/Transcript/TurnCheckpoint.swift:providerThreadID' # the provider's thread that held the turn being rewound
  'Sources/Core/Agent/PlanArtefact.swift:sourceID'               # the provider's plan item or tool-use token
  'Sources/Core/Presentation/AgentQuestionDigest.swift:answerID'  # the same opaque question answer id, carried for the closed line
)
# A stored property whose name ends in ID or Ids and whose type is a bare
# String. Trailing `{` is excluded by the `$` anchor, which is what leaves
# computed properties out.
# The pathspec keeps this one to `Sources/`, and .gitignore keeps `.build` out.
id_declaration='^[[:space:]]*(public |private |internal |fileprivate )?(var|let) [A-Za-z_]*([iI][dD]|IDs)[[:space:]]*:[[:space:]]*(String|String\?|\[String\]|Set<String>)[[:space:]]*(=[^{]*)?$'
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"
  allowed=0
  for path in "${id_type_allowed_files[@]}" "${id_type_allowed_lines[@]}"; do
    [ "$file" = "$path" ] && allowed=1
  done
  for name in "${id_type_allowed_names[@]}"; do
    case "$hit" in *" $name:"*|*" $name "*) allowed=1 ;; esac
  done
  for property in "${id_type_allowed_properties[@]}"; do
    [ "$file" = "${property%:*}" ] || continue
    name="${property##*:}"
    case "$hit" in *" $name:"*|*" $name "*) allowed=1 ;; esac
  done
  if [ "$allowed" -eq 0 ]; then
    echo "$hit" | show
    report "$file declares an id as a bare String. Give it a type from Sources/Core/Model/Identifier.swift, or add it to the list in $0 saying which id from outside Unified Dev it holds. A String id can be handed to any lookup that wants any other id, and the write that lands on no row says nothing at all."
  fi
done <<EOF
$(git grep --untracked -n -I -E "$id_declaration" -- 'Sources/*' || true)
EOF

echo "==> Views do not run subprocesses"
# The one rule CLAUDE.md states that had nothing behind it, which is exactly the
# state every rule in this file was in the day before it was written.
#
# The subprocess calls on `Git` and `Shell` are all async, so `await Git.` and
# `await Shell.` is the whole test: the pure helpers on the same types (Git.slug,
# Git.title, Git.countLines, Shell.which, Shell.environment) are synchronous and
# fall out for free without having to be listed.
#
# A view that needs one of these gets a helper type beside it, which is what
# FileRevert, FileIndex and TerminalPersistence are. Those live under Views/ and
# are the allowed list; they are not views, they are what a view calls instead of
# reaching for a process itself.
subprocess_allowed_files=(
  'Sources/UnifiedDev/Views/Inspector/FileRevert.swift'        # a helper type, not a view
  'Sources/UnifiedDev/Views/Center/Panes/FileIndex.swift'      # a helper type, not a view
  'Sources/UnifiedDev/Views/Terminal/TerminalPersistence.swift' # a helper type, not a view
)
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"
  allowed=0
  for path in "${subprocess_allowed_files[@]}"; do
    [ "$file" = "$path" ] && allowed=1
  done
  if [ "$allowed" -eq 0 ]; then
    echo "$hit" | show
    report "$file runs a subprocess from the view layer. Put it on a store, a model or a helper type beside the view (FileRevert and FileIndex are the shape), or add it to the list in $0. A decision taken inside a View is a decision nothing can test, and a body that shells out is a body that runs it again on every redraw."
  fi
done <<EOF
$(git grep --untracked -n -I -E 'await (Git|Shell)\.' -- 'Sources/UnifiedDev/Views/*' || true)
EOF

echo "==> a worktree is removed through the guard that protects an orchestrator"
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"
  if [ "$file" != 'Sources/Core/Workspace/WorkspaceManager+WorktreeRemoval.swift' ]; then
    echo "$hit" | show
    report "$file calls Git.removeWorktree directly. Use WorkspaceManager.removeWorktree(of:at:force:), which refuses the worktree of a project's orchestrator."
  fi
done <<EOF
$(git grep --untracked -n -I -F 'Git.removeWorktree' -- 'Sources/*' || true)
EOF

echo "==> a test's defaults live in its scratch directory"
# A throwaway UserDefaults suite named by hand leaves a plist in
# ~/Library/Preferences on every run, emptied or not. TestDefaults.make(_:) names
# the domain by a path inside the test process's scratch directory, which is
# removed when the process exits.
defaults_allowed_files=(
  'Tests/CoreTests/TestDefaults.swift'
  'Tests/CoreTests/TestDefaultsTests.swift'
)
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"
  allowed=0
  for path in "${defaults_allowed_files[@]}"; do
    [ "$file" = "$path" ] && allowed=1
  done
  if [ "$allowed" -eq 0 ]; then
    echo "$hit" | show
    report "$file opens UserDefaults(suiteName:) itself, which leaves a preferences file in ~/Library/Preferences on every run. Use TestDefaults.make(_:)."
  fi
done <<EOF
$(git grep --untracked -n -I -F 'UserDefaults(suiteName' -- 'Tests/*' || true)
EOF

echo "==> a link button goes through linkButton"
# The link button style draws NSColor.linkColor and ignores `.tint`, so a link
# button styled by hand is system blue beside prose links in the accent ink.
# `.linkButton()` in Theme.swift is where the ink is applied, with
# foregroundStyle, so it is the only door, and the door itself is held to that.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  file="${hit%%:*}"
  if [ "$file" = 'Sources/UnifiedDev/Design/Theme.swift' ]; then
    case "$hit" in *'.foregroundStyle(Palette.link)'*) continue ;; esac
    echo "$hit" | show
    report "$file styles linkButton() without foregroundStyle(Palette.link); the link style ignores a tint."
    continue
  fi
  echo "$hit" | show
  report "$file uses the link button style, which draws system blue however it is tinted. Use .linkButton()."
done <<EOF
$(git grep --untracked -n -I -E 'buttonStyle\( *(\.link|LinkButtonStyle\(\)) *\)' -- 'Sources/UnifiedDev/*' || true)
EOF

echo "==> a catch says something"
# `catch { }` compiles, runs, and is the only way an error in Swift can vanish
# without anybody being told. There are none in the tree today, which is why this
# is the one rule here written before the mistake rather than after it: a rule
# that starts at zero costs nothing to add and everything to add later.
#
# It is here rather than in `.swiftlint.yml` because SwiftLint cannot enforce it.
# `no_empty_block` is the nearest stock rule and it counts every empty `{ }`
# closure a SwiftUI action passes as the same thing, so it reports 103 findings
# here and not one of them is a swallowed error. A `custom_rules` regex says
# exactly this and is skipped on Linux, where the lint job runs, because matching
# one needs SourceKit: "Skipping enabled rule 'custom_rules' because it requires
# SourceKit and SourceKit access is prohibited", and then the job goes green. A
# rule that passes on the author's Mac and is not run by the thing that gates the
# merge is worse than no rule.
#
# Two spellings, because both are how it actually gets typed: the whole thing on
# one line, and the brace on its own line under it. The block says what it means
# in code: `try?` where the error is not worth catching, or the return, continue
# or log the catch exists for.
# Single quoted, and SC2016 has to be told so: `$0` in here is awk's whole line
# and not a shell parameter, so expanding it is the one thing this must not do.
# shellcheck disable=SC2016
empty_catch_awk='
  previous ~ /catch[^{]*\{[[:space:]]*$/ && $0 ~ /^[[:space:]]*\}[[:space:]]*$/ {
    printf "%s:%d:%s\n", FILENAME, NR - 1, previous
  }
  /catch[^{]*\{[[:space:]]*\}/ { printf "%s:%d:%s\n", FILENAME, NR, $0 }
  { previous = $0 }
'
while IFS= read -r file; do
  [ -n "$file" ] || continue
  if hits="$(awk "$empty_catch_awk" "$file")" && [ -n "$hits" ]; then
    echo "$hits" | show
    report "$file has a catch that does nothing. An error that is deliberately ignored says so in code, with try? where nothing is caught at all, or with the return, continue or log the block is there for; one that says nothing is a failure nobody will ever hear about."
  fi
done <<EOF
$(git grep --untracked -l -I -E 'catch[^{]*\{' -- 'Sources/*' 'Tests/*' || true)
EOF

echo "==> no subprocess is rooted at the home directory"
# A child process inherits a working directory, and both agent CLIs treat theirs
# as the project they have been pointed at. macOS attributes what a child reads
# to the responsible application, which is Unified Dev, so a CLI started in `~` asks
# for the user's own folders in Unified Dev's name and the user is asked about it by a
# system prompt naming Unified Dev.
#
# Four sites did it, and every one of them was reachable before a project had
# been added: both quota readers and the Codex model catalogue took
# `cwd: String = NSHomeDirectory()` as a default argument nobody reads, and the
# welcome window's sign-in terminal passed the home directory outright. None of
# them opens a file in the folder it stands in, so none of them needed a
# directory at all. `WorkspaceNamer` had already worked this out for the one call
# site its author was looking at, and said so in a comment, which is exactly the
# shape of decision that needs a rule rather than a paragraph.
#
# Narrow on purpose: this looks for a home directory handed to a parameter named
# `cwd` or `directory`, which is what every spawn site in the tree calls it. A
# path built out of `NSHomeDirectory()` to read a dotfile is not this mistake and
# is left alone.
if hits="$(git grep --untracked -n -I -E '(cwd|directory):[^)]*(NSHomeDirectory\(\)|homeDirectoryForCurrentUser)' -- 'Sources/*' || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "A subprocess rooted at the home directory. Nothing Unified Dev starts stands in the user's home: use AgentScratchDirectory for an ask with no workspace, or the workspace's own path."
fi

echo "==> an agent process is launched under the account that was chosen"
# AgentAccountEnvironment.apply strips the variables a host injects and, for an
# account that is not the CLI's default, points the process at that account's
# directory. A launch built without it keeps running on the wrong account and no
# test notices. Every construction of an AgentLaunch or a WorkspaceNamerLaunch has
# to contain a call to AgentAccountEnvironment.apply( in its own text: the span
# between its parentheses, minus the spans of any construction nested inside it,
# which cannot lend theirs. Comments and string contents are blanked first, so a
# mention there counts for nothing. The check is that the call is present in the
# construction, not that its result is what the construction uses.
#
# The reader is not a Swift parser. It understands line and nested block comments,
# single and multi-line strings, raw strings with their hashes, and escapes. It
# does not understand string interpolation: whatever sits inside a string,
# interpolation included, is blanked. It cannot tell in general that it has
# misread. It notices three symptoms: a string or comment still open at the end of
# the file, a single-line string cut by a newline, and a construction whose
# parentheses never balance. Any of them makes the awk script exit non-zero and the
# rule then reports the file as not checked. Valid Swift can produce them too,
# because a literal nested inside an interpolation shifts the reader's idea of
# where strings begin and end: Sources/Core/Persistence/SettingsDocument.swift
# line 218 does, and the file is skipped only because it has no construction. A
# misreading that leaves none of the three symptoms is not noticed, and a nested
# literal that happens to keep the quotes paired is read as a string, so the code
# inside that interpolation is not read.
#
# Not seen, none with a case in the tree today: a construction written inside a
# string interpolation; `let a: AgentLaunch = .init(...)` and `AgentLaunch.init(`;
# a name that merely ends in AgentLaunch, which the word boundary skips. A process
# started without an AgentLaunch (a bare StreamingProcess or Shell.run naming
# claude, codex or grok) is not seen either: seeing it needs an exception list for
# the screen capture, the language servers, the updater and the sleep helper, and
# a list like that rots into a lie.
#
# The second check is on string literals only: the quoted names CODEX_HOME,
# GROK_HOME and CLAUDE_CONFIG_DIR may appear in Sources only in
# AgentAccountEnvironment and in TranscriptSources, which reads them to find the
# default directories for spend. A name built from pieces is not seen.
launchers="$(git grep --untracked -l -I -E '(AgentLaunch|WorkspaceNamerLaunch)\(' -- 'Sources/*' || true)"
for file in $launchers; do
  if ! lines="$(awk -f Tools/agent-launch-constructions.awk "$file")"; then
    report "Tools/agent-launch-constructions.awk failed on $file, so its launches were not checked."
    continue
  fi
  for line in $lines; do
    report "$file:$line builds an agent launch with no call to AgentAccountEnvironment.apply inside it."
  done
done
if hits="$(git grep --untracked -n -I -E '"(CODEX_HOME|GROK_HOME|CLAUDE_CONFIG_DIR)"' -- 'Sources/*' ':!Sources/Core/Agent/AgentAccountEnvironment.swift' ':!Sources/Core/Spend/TranscriptSources.swift' || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "An account directory variable named outside AgentAccountEnvironment. Ask it for the value instead of reading or writing the variable."
fi

echo "==> British spelling"
# Words with an American spelling that has no other job in this codebase.
# Deliberately absent: colour, behaviour, centre, dialogue, catalogue and
# licence, because Apple's own API is spelled the American way and the tree is
# full of foregroundColor, scrollBehavior and NSTextAlignment.center.
american=(defense offense fulfill fulfillment skeptical acknowledgment maneuver
          labeled modeled traveled centered analyze analyzing paralyze
          enrollment installment recognize recognizes recognizing)
# These three do have a job in code today: "Favorites" names a Finder sidebar
# section, ToolRefusal parses the literal string "canceled" out of agent output,
# and gray names a CoreGraphics colour space. In prose there is no such excuse.
american_in_prose=(favorite favorites gray canceled)

for word in "${american[@]}"; do
  if hits="$(git grep --untracked -n -I -i -w "$word" -- ':!.claude' ':!*fixtures/*' ':!Tools/house-rules.sh' || true)" && [ -n "$hits" ]; then
    echo "$hits" | show
    report "American spelling: $word."
  fi
done
for word in "${american_in_prose[@]}"; do
  if hits="$(git grep --untracked -n -I -i -w "$word" -- '*.md' ':!.claude' ':!Tools/house-rules.sh' || true)" && [ -n "$hits" ]; then
    echo "$hits" | show
    report "American spelling in prose: $word."
  fi
done

echo "==> a watched line is still the line it names"
# Sources/Core/Presentation/UnboundedHeightSubject.swift records twelve views by
# file and line, because #248 is about a construction that cannot be told from a
# healthy one without measuring it. A line number in the core that names a file
# in the app target goes stale the first time anybody inserts a line above it,
# and nothing in either target would notice: the list is a literal, and a test
# over a literal only ever agrees with itself. This reads each entry off disk.
subjects=Sources/Core/Presentation/UnboundedHeightSubject.swift
if [ -f "$subjects" ]; then
  while IFS='|' read -r file line; do
    [ -n "$file" ] || continue
    if [ ! -f "$file" ]; then
      report "$subjects watches $file, which is not there."
      continue
    fi
    total="$(wc -l < "$file" | tr -d ' ')"
    if [ "$line" -gt "$total" ]; then
      report "$subjects watches $file:$line, past its $total lines."
      continue
    fi
    held="$(sed -n "${line}p" "$file")"
    case "$held" in
      *fixedSize*|*frame\(maxWidth*) : ;;
      *) echo "  $file:$line$held" | show
         report "$subjects watches $file:$line, which no longer asks for a height." ;;
    esac
  done < <(
    awk '
      /file: "Sources\/UnifiedDev/ { match($0, /"[^"]+"/); watched = substr($0, RSTART + 1, RLENGTH - 2) }
      watched != "" && /line: [0-9]+,/ { match($0, /[0-9]+/); print watched "|" substr($0, RSTART, RLENGTH); watched = "" }
    ' "$subjects"
  )
fi

echo "==> the store feed a reload watches is the set the core declares"
# A domain missing from that set is an agent running under one account while the
# picker still names another, and nothing in Tests/ reaches the app target. The
# set belongs in the Core, where a test can hold it; this holds the one line that
# passes it.
observer=Sources/UnifiedDev/State/AppModel.swift
if [ -f "$observer" ] &&
   ! grep -q 'store.changes(of: StoreDomain.projectListFeed)' "$observer"; then
  grep -n 'store.changes(of:' "$observer" | show || true
  report "$observer must watch StoreDomain.projectListFeed, not a set written here. A domain dropped from a literal is a picker that keeps naming the account the agent stopped using, and nothing in Tests/ can see it."
fi

echo "==> only the project's settings pane turns the orchestrator's switch"
# A switch that lets an agent's commands run unseen is the one setting an agent
# must not be able to reach. Saving it from anywhere else, or writing settings
# from the bridge at all, would hand that to whoever calls the code.
if hits="$(git grep --untracked -n -I -e 'OrchestratorUnaskedCommands\.save' -e 'OrchestratorUnaskedCommands\.key' -e 'orchestratorRunsCommandsUnasked' -- 'Sources' ':!Sources/Core/Agent/OrchestratorUnaskedCommands.swift' ':!Sources/UnifiedDev/Views/RepoSettings/RepoOrchestratorSection.swift' || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "OrchestratorUnaskedCommands is saved from RepoOrchestratorSection and nowhere else."
fi
echo "==> only the project's settings pane turns the pull request auto fix switch"
# Sending a request built from CI output with nobody looking is what this switch
# allows, so an agent must not be able to reach it either.
if hits="$(git grep --untracked -n -I -e 'PullRequestAutoFixSetting\.save' -e 'PullRequestAutoFixSetting\.key' -e 'pullRequestAutoFix"' -- 'Sources' ':!Sources/Core/GitHub/PullRequestAutoFixSetting.swift' ':!Sources/UnifiedDev/Views/RepoSettings/RepoPullRequestAutoFixSection.swift' || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "PullRequestAutoFixSetting is saved from RepoPullRequestAutoFixSection and nowhere else."
fi
bridge_files="$(git grep --untracked -l -I -e 'ForBridge(' -e ': BridgeToolHandling' -e 'BridgeToolbox(' -- 'Sources' || true)"
if hits="$( { git grep --untracked -n -I 'setSetting(' -- 'Sources/Core/Bridge' 'Sources/UnifiedDev/State/AppModel*.swift'; [ -z "$bridge_files" ] || echo "$bridge_files" | xargs grep -n -H 'setSetting(' ; } || true)" && [ -n "$hits" ]; then
  echo "$hits" | sort -u | show
  report "The bridge does not write settings: not in the core, not in AppModel, which serves the app's half of it, and not in a file that serves a tool. An agent calls it, and some of those settings decide what an agent may do."
fi
app_toolbox=Sources/UnifiedDev/State/AppModel+WorkspaceBridge.swift
if hits="$(git grep --untracked -n -I 'BridgeToolbox(handlers:' -- 'Sources' ':!Sources/Core/Bridge/BridgeToolbox.swift' ":!$app_toolbox" || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "Bridge tools are added in BridgeToolbox.standard or in $app_toolbox, where the reach suite's list is checked against them."
fi
reach_handlers=Tests/CoreTests/OrchestratorUnaskedReachSupport.swift
if [ -f "$app_toolbox" ]; then
  while IFS= read -r tool; do
    if [ ! -f "$reach_handlers" ] || ! grep -qE "^ *$tool( *[({]|\.)" "$reach_handlers"; then
      echo "$app_toolbox: $tool"
      report "$tool is served by the app and not built in $reach_handlers, so the reach suite never calls its handler."
    fi
  done < <(grep -oE '\b[A-Z][A-Za-z]*Tool\b' "$app_toolbox" | sort -u)
fi

echo "==> only the profile's settings section turns a profile's bridge switch"
if hits="$(git grep --untracked -n -I -e 'ProfileBridgeSwitch\.save' -e 'ProfileBridgeSwitch\.key' -e 'reachableFromOtherProfiles' -- 'Sources' ':!Sources/Core/Workspace/ProfileBridgeSwitch.swift' ':!Sources/UnifiedDev/Views/Chrome/Settings/ProfileBridgeSection.swift' ':!Sources/Core/Preview/PreviewScenarioSeeder+Profiles.swift' || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "ProfileBridgeSwitch is saved from ProfileBridgeSection and, in a seeded preview, by the scenario seeder, and nowhere else."
fi

echo "==> no async closure literal is a default argument in the core"
async_default='\)[[:space:]]*async([[:space:]]+throws)?([[:space:]]*->[^={]+)?[[:space:]]*=[[:space:]]*\{'
stored='^[^:]+:[0-9]+:[[:space:]]*((public|private|fileprivate|internal|nonisolated|static|lazy)[[:space:]]+)*(let|var)[[:space:]]'
if hits="$(git grep --untracked -n -I -E "$async_default" -- 'Sources/Core/*.swift' 'Sources/bridge/*.swift' | grep -vE "$stored" || true)" && [ -n "$hits" ]; then
  echo "$hits" | show
  report "An async closure literal as a default argument is copied into every client and can abort the test process (swiftlang/swift#92017). Name it as a static let and default to that."
fi

echo "==> an extension of a debug-only type is debug-only too"
debug_types="$(git grep --untracked -l -I '^#if DEBUG' -- 'Sources/*.swift' | xargs grep -h -oE '^(public |final |@MainActor )*(struct|enum|class|actor) [A-Z][A-Za-z0-9]*' 2>/dev/null | awk '{print $NF}' | sort -u || true)"
for type in $debug_types; do
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    if ! grep -q '^#if DEBUG' "$file" && ! grep -qE "^(public |final |@MainActor )*(struct|enum|class|actor) $type([^A-Za-z0-9]|$)" "$file"; then
      grep -n -E "^extension $type([^A-Za-z0-9]|$)" "$file" | sed "s|^|$file:|" | show
      report "$file extends $type, which exists only under #if DEBUG, from outside #if DEBUG. The release build cannot compile it."
    fi
  done < <(git grep --untracked -l -I -E "^extension $type([^A-Za-z0-9]|$)" -- 'Sources/*.swift' || true)
done

if [ "$findings" -gt 0 ]; then
  echo
  echo "$findings house rule violations."
  exit 1
fi
echo
echo "House rules pass."
