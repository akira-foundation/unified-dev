# Unified Dev

Project skills for development builds, releases and Swift work are indexed in [AGENTS.md](AGENTS.md).
Claude and Codex share the same skill files; load only the skill and references relevant to the task.

A macOS 26 app for running coding agents in git worktrees. One window: a sidebar of projects and
their workspaces, a transcript in the centre, a terminal, an inspector. A workspace is a real
worktree on disk, which is why so much of what follows is about not destroying one.

Longer documents, pointed at rather than repeated here: `README.md` for what the app is,
`RELEASING.md` for signing and notarising, `docs/CODEX.md` for the Codex app-server
protocol as measured, `docs/GROK.md` for Grok's ACP over stdio, `docs/BITBUCKET.md` for the Bitbucket CLI and how a pull request there is read, `docs/PROTOCOL.md` for Claude Code's stream-json,
`docs/AGENTS-INTEGRATION.md` for how the five CLIs are detected, `docs/PREVIEW-APPS.md` for the
preview app every worktree can build and the scenario it is seeded with, `docs/CHAT-SEGMENTS.md` for how one chat
is run by several agents in turn and what the agent that comes in is told, `docs/BRIDGE.md` for the MCP
bridge an agent calls back in through and which callers may call what, `docs/PROFILES.md` for the groups of projects the window shows one at a time, `docs/PLAN.md` for what was
built and in what order, `docs/start-from.html` for the design note the create sheet's source picker
was drawn from, which is a page to open in a browser rather than to read here.

## Three targets, and the line between them

`Sources/Core` is everything that is not a view: `Store`, `Git`, `Shell`, `WorkspaceManager`,
the agent protocols, the parsers, the models. **It never imports a UI framework.**

`Sources/UnifiedDev` is the SwiftUI app and the only target allowed to import SwiftUI, AppKit
or SwiftTerm.

`Sources/bridge` is the MCP stdio shim an agent CLI launches as a child process, which
relays lines to the running app over a unix socket. Three lines of `main.swift`; everything worth
testing is `BridgeShim` in the core. It is a relay with nothing to draw, so it is held to the same
line as the core.

`make lint` holds that line for both, and it looks for the framework rather than for a literal,
because `import Cocoa` re-exports the whole of AppKit and `import class AppKit.NSView` names
AppKit without containing the words next to each other. SwiftTerm needs no rule: only
the app target declares it in `Package.swift`, so importing it anywhere else does not link.

`Tests/CoreTests` depends on `Core` alone. Read `Package.swift`: the test target has one
dependency and it is not the app. **So a decision taken inside a view is a decision nothing can
test.** When behaviour needs a test, and most does, it belongs in Core as a pure function or a
type, with the view calling it. That is the whole reason the split exists.

`Tests/BrowserScriptTests` is the one exception, and it is one because of what it tests rather
than in spite of the rule. The browser tools inject JavaScript into a page, written out by hand in
`BrowserAgentScript`, and the only thing that can say what a script does to a page is a page. So
that target depends on `Core` alone as well and links WebKit on top, loads fixture HTML into an
offscreen `WKWebView` and asserts what each script answers. It holds no decision of its own: every
answer goes through the same `Core` function the app reads it with. `make test-browser` runs it,
and `./Tools/test-browser-scripts.sh Secrecy` runs one suite. It is a second target rather than a
directory in the first because `Tools/test-core.sh` mirrors the core into a package that must keep
the line above, and a target that imports a UI framework cannot be in it.

## Build and test

Everything real is a script in `Tools/`; the `Makefile` is the index.

    make            list the targets        make lint       Tools/house-rules.sh
    make build      compile every target    make test       the Core suite
    make swiftlint  Tools/swiftlint.sh      make test-browser  the scripts, in a real page
    make app        assemble a debug .app   make run        release .app, launched
    make master     install /Applications/UnifiedDev.app   (see the guard below)
    make dev-fast   install current edits as Unified Dev (Dev) (debug)
    make dev        install committed HEAD as Unified Dev (Dev) (release)
    make dev-db     copy the real database into the dev copy
    make preview    build this worktree's own preview app into .build/preview
    make preview-clean  remove that preview and everything it made
    make release    sign, notarise and staple a zip and a disk image into dist/
    make dmg        wrap the newest built .app in the disk image

Anything that takes an argument is run directly: `./Tools/test-core.sh DiffParser`,
`./Tools/master.sh v0.3.0`, `./Tools/dev-build.sh --no-launch`.

`./Tools/test-core.sh` mirrors the core sources into a throwaway package with no app target, so one
broken view cannot stop the core suite. Its head documents the environment it reads: `UD_TEST_ID`
for a stable work and build directory, `UD_TEST_RUNS` to run the suite repeatedly and shake out
flakes, `UD_LOCAL_AGENTS=1`, `UD_LOCAL_SETTINGS=1` and `UD_LOCAL_SKILLS=1` to assert
against this machine, with `UD_LOCAL_PROJECT` naming the checkout the last of those reads,
`UD_LIVE=1` to drive the real `claude` binary (**this costs money**), and
`UD_TEST_SWIFT_ARGS` for flags like `--sanitize=thread`.

**A mutating call cannot go inside `#expect`.** The macro rewrites its argument into a closure
taking the value immutably, so `#expect(flow.advance())` fails to compile with "cannot use mutating
member on immutable value: `$0` is immutable", and the error is reported against expanded code
rather than against the line you wrote. Lift it: `let moved = flow.advance()` and then
`#expect(moved)`. This has cost two separate agents an hour each, on `TranscriptRowHeights` and on
`OnboardingFlow`, and it is the sort of thing nobody deduces twice.

**A green `make test` does not mean the app compiles.** The mirror has no app target, so the
core suite has stayed green while `Sources/UnifiedDev` was broken, four times, every one of them a
widened enum leaving a switch in a view non-exhaustive. Run `make build` before committing
anything that adds a case to an enum.

**And none of the three compiles the other two.** `swift build` does not build a test target, and
each of the two test scripts writes a mirror that declares its own and not the other's, so a
widened enum can leave `Tests/BrowserScriptTests` non-exhaustive with `make build` and `make test`
both green. That is the same mistake in a third place: `make test-browser` is the only thing that
compiles it.

**The suite is `./Tools/test-core.sh`, and a bare `swift test` is not it.** `BridgeRegistration.shimPath`
reads `UD_BRIDGE_SHIM`, and failing that looks for an executable named `bridge` beside the running
executable, which under `swift test` is inside the `.xctest` bundle with the built `bridge` two
directories up. Nothing is found, `BridgeServer.register(askSession:)` returns nil, and the one
`BridgeAskIdentityTests` case that registers a chat fails its `#require`; `BridgeShimTests` and
`LiveBridgeTests` are gated on the shim and merely skip. `test-core.sh` builds the `bridge` product and
names it in `UD_BRIDGE_SHIM`, which is why it is green there, green in CI, and what the pull request
gate runs.

Zero warnings, and `make lint` green, before anything is committed.

**`make lint` and `make swiftlint` are two different linters and both have to pass.**
`Tools/house-rules.sh` is the conventions no off the shelf tool knows: no em dashes, British
spelling, typed ids, a view that does not run a subprocess, only the app target importing a UI
framework. SwiftLint is the half every Swift codebase shares, and `.swiftlint.yml` is tuned rather
than default, because the defaults reported 1,634 violations here. The head of that file carries
the count each disabled rule produced and the reason it is off, so a rule is argued with rather
than guessed at. Both run in the `lint` job of `.github/workflows/test.yml`, on the Linux runner.

SwiftLint is not installed by anything here. `brew install swiftlint`, or take the binary from the
releases page; `Tools/swiftlint.sh` says so and stops rather than installing it for you. CI pins
its own copy. `./Tools/swiftlint.sh --fix` applies what SwiftLint can correct itself, and the
diff has to be read: it once rewrote `let _ =` inside a `@ViewBuilder` into code that does not
compile.

**A rule of ours goes in `Tools/house-rules.sh`, never in a `custom_rules:` block.** SwiftLint
matches a custom rule through SourceKit, there is no SourceKit on Linux, and the lint job prints
"Skipping enabled rule 'custom_rules'" and goes green. A rule that passes on the author's Mac and
is not run by the thing that gates the merge is worse than no rule, so `.swiftlint.yml` has no
such block and says why.

## Why there is no Xcode project

Because there is nothing left for one to do, and this was measured rather than assumed. The
question keeps coming back, so the answer is written down here.

**Xcode already has the targets and the schemes.** Open `Package.swift` in Xcode and it builds,
runs, debugs, profiles and previews. `xcodebuild -list` in this directory, with no `.xcodeproj`
anywhere, answers with four schemes: `Unified Dev`, `bridge`, `Core` and `Unified Dev-Package`.
Apple's own position is in the tooling: `swift package generate-xcodeproj` was removed years ago,
and `swift build --build-system xcode` is labelled "discouraged" in its own help text.

**The one thing a project file really does buy is the recommended-settings prompt, and here it
would land on a build nobody ships.** That prompt is a `PBXProject` mechanism and nothing else:
the strings live in `DevToolsCore.framework` next to `PBXProjectAttribute_LastUpgradeCheck`,
`PBXProject setLastUpgradeCheck:` and `_runUpgradeChecksIfNecessary`, and what it compares is the
`LastUpgradeCheck` stamp in `project.pbxproj` against the Xcode you opened it with. A package has
no `project.pbxproj`, so there is nothing to stamp, which is why the prompt never appears. It is
a real feature and it is genuinely unavailable here; the question is what it would modernise. It
edits `XCBuildConfiguration`, which is a set of build settings that **`swift build` never reads**.
`make build`, `Tools/build.sh`, `Tools/test-core.sh`, `.github/workflows/test.yml` and
`release.yml` all go through SwiftPM, so a project accepting a recommended setting and the app
everybody actually installs would be two different builds, free to disagree, with only the project
file being told about it.

**And a checked-in project file rots here faster than most.** This repository took 728 commits, 21
merges and 964 new Swift files in its first eight days, with several agents in parallel worktrees
merging into `main`. Xcode 26 does remove the oldest objection, because a
`PBXFileSystemSynchronizedRootGroup` picks files up from a folder without listing them, so the
"every new file has to be added by hand" complaint is out of date and should not be repeated. What
does not go away is that the file would be a second description of a build that only one person
opens, next to a `Package.swift` that everything else reads.

**Generating it instead does not rescue the argument, it kills it.** XcodeGen or Tuist from a
spec, or a `Tools/xcodeproj.sh` that writes one on demand, would avoid the merge conflicts, but the
whole benefit above is a stamp Xcode writes back into `project.pbxproj` and compares next time.
Regenerate the project and that stamp goes with it, so the modernisation prompt you wanted either
never fires or fires every time. A generated project is the right answer to a different question.

**What to do instead, when the toolchain moves.** The package equivalent of accepting recommended
settings is `swift-tools-version` and the language mode at the head of `Package.swift`, which are
`6.2` and `.swiftLanguageMode(.v6)` today, plus `.enableUpcomingFeature` for anything the next
release wants opted into. CI already refuses to build on an Xcode older than 26 and compiles with
`-warnings-as-errors`, so a toolchain that changes its mind about something says so on the next
push rather than in a dialog nobody opened.

`.gitignore` has ignored `*.xcodeproj` since before this was written. Leave it there. If you want
Xcode, open `Package.swift`.

## Where a green answer comes from

Run tests locally, and run the ones that cover what you touched:
`./Tools/test-core.sh DiffParser` rather than `make test`, most of the time. **The full suite is
not a thing to sit and repeat.** The owner is working at this Mac while you run, several agents
build at once, and a day of that took the load average to 205. A sweep of everything on every edit
is how his machine stalls, and the machine stalling costs more than the answer is worth.

**The green that counts is CI on a pushed branch.** `.github/workflows/test.yml` builds the app
target with `-warnings-as-errors`, runs the house rules, parses every script and runs the whole
core suite and then the browser scripts on a macOS 26 runner, on hardware that is not his. Push,
wait for it, and read what it says before calling anything done. `gh run watch` and `gh run list --branch <name>` are how you
wait without polling the browser.

**Work is based on `develop`.** A branch is cut from it and its pull request targets it, and
`main` receives a `release/*` merge and nothing else. `.github/workflows/branch-policy.yml` is
what holds that, and it is worth reading rather than guessing at: which base a branch may target
depends on its prefix, a `feat/*` or `fix/*` may also target a `milestone/*` or a `release/*`
branch, and a prefix the file does not recognise, `ci/*` among them, may target `develop` alone.

`.github/workflows/test.yml` runs on **push to `develop` and to `main`, on pull request, and from
the Actions tab**, and `release.yml` calls it on every tagged commit and publishes nothing until it
is green there. A pull request run builds the head already merged into its base rather than the
head, because the `ref:` its checkout steps name is empty unless `release.yml` passed one. So the
merge a pull request would produce is tested, and where the branch protection's up to date rule was respected the merge that lands has
that same tree. Where it was not, and `enforce_admins` is off on `develop` so it binds nobody,
the tree that lands was built by nothing: that was a third of the merges over thirty days, and
the push on `develop` is there to catch them. `main` was on that list throughout and `develop` was
not, which is the whole of what this fixed. A branch pushed with no pull request open is built
only by asking for it in the Actions tab, so opening the pull request is part of asking for the
answer rather than a step after it.

The nightly workflow is separate and gates nothing: Thread Sanitizer, coverage and dead code, on a
schedule, because they are too slow to put in front of a push. Read it when you want those
questions answered, and do not wait on it.

## Persistence goes through `Store`

One actor, one SQLite file, and one rule: **`upsert` creates a row, `update` modifies one.**

`upsert` writes every column from the value it is handed, so it is correct only when that value was
built there and then. Hand it a row read a few seconds ago and it carries every column back to what
it looked like then. `update(workspaceID:)` and its siblings read the row inside the actor, apply
the change and write, with no suspension in between.

This is not tidiness. A workspace row has a diff stat refresh writing every few seconds, an archive
that takes seconds of disk work, a panel somebody sits in for a minute, and an agent turn that runs
for ten. Whole-value writes rolled each other back, and the worst of it was a row that said a
workspace was live after its worktree had been deleted. `Tests/CoreTests/WorkspaceWriteIsolationTests.swift`
is that bug written down: a write changes the columns it names and no others. Add a column and
`update` picks it up; reach for `upsert` on an existing row and the bug is back.

The account an agent runs under is written in two different shapes, and they are not the same thing.
A **choice** by the owner lives in `repo_agent_accounts`, one row per project and provider, and
changes only through `chooseAgentAccount(_:forRepo:)`, which takes a `ChosenAgentAccount` so the
provider is always the chosen account's own. A workspace has no choice of its own: every workspace
and chat of a project runs the project's account. A
**record** of where a chat's history lives is `sessions.account_id`, and changes only through
`update(sessionID:accountID:)`, through `switchSegment` or through `forgetAgentAccount`. `upsert` writes that column when it
inserts a new session and leaves it out of `ON CONFLICT` on purpose, and the closure form of
`update` ends in the same write, `writeSession`, so
`update(sessionID:) { $0.accountID = x }` compiles, looks like the normal route and changes nothing.
The property is `internal(set)` so the same line does not compile outside `Core`. `Repo` and
`Workspace` have no such property at all: the choice is not on their row, so a stale whole-value
write cannot carry one back.

Deleting an account frees both shapes, and by two different rules. A choice row goes with the account,
because `account_id` in the choice table is `NOT NULL REFERENCES agent_accounts(id) ON DELETE
CASCADE`; it goes with the project too, by a second cascade on `repo_id`, which is why no choice
outlives its owner. `forgetAgentAccount` refuses a default and
sets `sessions.account_id` and `session_segments.account_id` to NULL, because that chat's history stays
where it is. It also clears `agent_session_id` and sets the cursor to -1 on every segment that account
held, and on the active segment and `sessions.agent_session_id` of every chat recorded on it, since
`update(sessionID:accountID:)` does not touch the segment. The next send of such a chat carries the
whole conversation instead of failing a turn.

The id of a default account is `"default." + provider.rawValue`, so `AgentKind.rawValue` is written
into the database in two ways: a column that holds the case, and a column that holds an account id
built from it. **Renaming a case damages both, silently, and in two different ways.** A column read
behind a `guard let` makes its row vanish: the account drops out of `agentAccounts()`, the owner's
choice out of `agentAccountChoices()`, the reading out of the quotas. A column read with
`?? .claudeCode` does something worse, because it does not look broken: a Codex chat reopens as
Claude Code, and its spend is counted against the wrong agent. The rows that vanish are still on
disk, choices until their project is deleted and accounts for ever, because nothing
owns those.

**Do not count those columns here.** This paragraph has been wrong four times, each time somewhere
different, because a list written from memory rots the moment somebody adds a table. The list lives
in `AgentKindColumns.aRenameMustMigrate`, and `AgentKindColumnsTests` walks the built schema for
every column that holds the case or carries a foreign key into `agent_accounts` and refuses to pass
unless the two agree. Add a table with a `provider` column or an account of its own and that test
fails until it is declared. Whoever renames a case migrates what that value names, and reads each
one to see which of the two things it would do.

## Views

A type conforming to `View` does not run a subprocess. `Shell` and `Git` are reached from a store,
a model or a helper type beside the view (`FileRevert`, `FileIndex`, `TerminalPersistence`, or
`WorkspaceModel` over in `State/`), never from a `body` or a button action. `make lint` holds this
one too, by looking for `await Git.` and `await Shell.` under `Sources/UnifiedDev/Views/`: the subprocess
calls are all async and the pure helpers on the same types are not, so the test costs no exception
list of its own. A terminal is the one process that starts synchronously, so the rule also names
`TerminalLaunch(` and `startProcess(`; a login terminal is handed a `LoginCommand` the core already
parsed, and `LoginTerminal` and `TerminalView` are where the process is actually started. The five
of those that live under `Views/` are named in the allow-list because they are what a view calls
**instead** of reaching for a process itself; `WorkspaceModel` is outside that path, so the rule
never sees it and needs no entry. `CreateWorkspaceView` was the last exception, calling
`Git.branches` from its own `.task`; that loading and both branch decisions it fed are
`WorkspaceStartContext` in the core now, tested, so its entry came off.

## Where a file goes

`Sources/Core` is grouped by subject, one directory deep and no deeper:

    Agent/          running one, its events, its quotas, its turns; Codex/ is its own protocol
    Bridge/         the unix socket, the MCP tools an agent calls back in with
    Git/            git itself, and everything read out of a diff
    GitHub/         gh, pull requests, checks
    Forge/          which host a repository is on, and Bitbucket through bkt
    Workspace/      creating, starting, archiving, restoring, and a project's own settings
    Transcript/     what a turn is made of: rows, tools, subagents, attachments, prompts
    Persistence/    Store, SQLite, the settings file, the old app's leftovers
    Model/          the row types, the typed ids, and the lifecycle rules over them
    Presentation/   decisions that exist for the window and hold no UI framework
    Canvas/         the canvas document and its format, the keeper, history, comments and their delivery, export
    Ocean/          the chart, which is its own small world
    Preview/        a worktree's preview app: its identity and the scenario it is seeded with
    Spend/          what the agents cost: the transcripts, the prices, and the board over them
    System/         this Mac: the shell, notifications, updates, other applications
    Support/        small things with no subject of their own

It was 274 files in one directory, which is not a structure, it is a list. The grouping is by
**what a file is about**, never by what it is: no `Extensions/`, no `Helpers/`, no `Protocols/`,
because those tell a reader nothing they could not see from the file itself.

`Spend/` needs a sentence too, because it holds its own presentation: the lines, the formats and
the bar heights of the spend screen live there rather than in `Presentation/`, for the same reason
`Ocean/` holds its chart. The subject is one small whole, and splitting its words from its sums
would mean reading two directories to change one screen.

`Presentation/` is the one that needs a sentence. It holds decisions the window needs and that
have no `import SwiftUI` in them: which tab is next, what the sidebar's summary line says, whether
two colours are far enough apart. They are here rather than beside the views for the reason the
whole three-target split exists, and they are in their own directory rather than mixed into the
subjects so that "this is a view's decision, moved" stays visible.

`Sources/UnifiedDev` is grouped the same way, by **pane rather than by kind**. `Views/` holds one
directory per region of the window (`Sidebar`, `Center`, `Inspector`, `Home`, `Transcript`,
`Terminal`, `Chrome`, `Tabs`) and one per thing that gets a window or a sheet of its own
(`Archive`, `Code`, `DocumentPreview`, `Markdown`, `Oceans`, `OpenIn`, `RepoSettings`, `Spend`), and the
two that outgrew a single directory are split by what they are for rather than by what they are:
`Center/Composer`, `Center/Panes`, `Center/Attachments`, `Center/Browser`, `Center/Canvas`, `Center/NewWorkspace`; `Chrome/Window`,
`Chrome/Settings`, `Chrome/MenuBar`, `Chrome/App`, `Chrome/Feedback`, `Chrome/Notices`.

Four directories sit beside `Views/` and are not panes, because none of them is drawn in one
place. `Design/` is the theme and the snapshot galleries, `State/` is `AppModel` with its
extensions and the two models under it, `Intents/` is App Intents, Shortcuts and the Services menu,
and `System/` is the app target's half of talking to this Mac.

A directory with one file in it is not a subject. Leave it at the folder's root and give it one
when a second arrives. `Tools/house-rules.sh` names about twenty of these paths in its allow-lists,
so a move has to update them: `make lint` says so immediately, which is the point.

## One subject per file

`AppModel` reached 2,421 lines: four enums and structs stacked above the class, fourteen `MARK`
sections inside it, and not one of those was a decision anybody took. Each arrived as three methods
put beside the last three, because the file was already open.

**A type gets a file. A subject gets a file.** A type that has grown a second subject is split with
an extension in the same directory, named `Type+Subject.swift`. `AppModel+ProjectIcons.swift` and
`AppModel+TranscriptSearch.swift` are the shape, each opening with a paragraph saying what the file
is for; `AppModel+Naming.swift` is the same split without that paragraph, and is the poorer for it.
What stays in `Type.swift` is what nothing else can hold: the stored properties, because Swift has
none in an extension, the initialiser, and the members that genuinely coordinate between subjects.

Two things decide where the cut goes, and neither is taste. A stored property cannot move, so a
grouping that needs one moved is the wrong grouping. And `private` is file scoped, so every member
that leaves either takes the private state it touches with it or forces that state wider. Count the
widenings before splitting. Five files that keep a type's internals are worth more than nine that
publish them, and a cut that widens the properties whose doc comments say they have one writer is a
cut in the wrong place. `Store` is the case that settles it: 2,603 lines around one `private let
db`, where every extension would have to publish the connection, so it stays as it is.

A long file is not the failure, and `make lint` has no rule here because every threshold tried
fired on files that were right. A 1,200 line ceiling needs an exception list the day it is written,
and half of what goes on that list is correct as it stands. Counting top-level types fires on
`CodexEvent.swift` at twenty-two, `Models.swift` at fourteen and eighty other files besides, every
one of them fine. `Store` at 2,603 lines is right and `AppModel` at 2,421 was not, and no number
tells them apart. The failure is a file nobody can find anything in. The question before adding to
one is whether the thing being added is what the file is about, and the answer to no is a new file
rather than a longer one.

## Comments

**Code carries no comments.** Not a paragraph on a type, not a docblock, not a note above a line.
The commit-guard scan refuses them, and a file that has to be argued with the gate on every commit
is a file nobody edits twice.

`docs/` is technical and usage documentation: what a thing is, how it works, how it is used. What
was tried, what broke and what the measurement was goes in a comment on the issue the work belongs
to, where the next person looking at that decision will be. A `// TODO:` of one line is the only
thing left in a source file, and even that is better as an issue.

## Prose

**No em dashes and no en dashes anywhere.** Use a comma, a full stop or brackets. **British
spelling.** The app is called Unified Dev, and it had another name before it was renamed, which still
arrives from stale memory. `make lint` checks all three, knows the old name so this file does not
have to, and names the file and line.

## Do not take over the machine

The owner is sitting at this Mac, working, while you run. Anything that takes focus, moves the
pointer, opens or closes a window, launches or quits an application, or puts a window in front of
what he is reading is an interruption to a person, not a step in a task. **Ask before doing any of
it.**

Needs permission every time: launching an app in a way that activates it (`open -g` does not, and
is the one to reach for), `NSApp.activate` or anything that makes a process frontmost, quitting or
signalling any application, sending a keystroke or a click or any synthetic event, capturing or
recording the **display**, changing a system setting including the appearance, and opening a
browser or an editor.

Needs no permission: offscreen rendering, anything headless, and capturing **your own** window by
its window id after opening it with `open -g`.

If a piece of work cannot be verified without one of these, say so and stop. An honest "I could
not photograph this" is a better outcome than an interruption, and it is what several agents have
correctly chosen. A capture that films the display shows whatever is in front of your window,
which has twice turned out to be the owner's own screen.

## The dev build, and the rules that keep the owner's data alive

Unified Dev is developed in Unified Dev. The app you are running inside is the owner's, holding his real
projects, and he is using it right now.

**Never touch any of these.** `/Applications/UnifiedDev.app`. `~/Library/Application Support/Unified Dev/`.
The `io.akira.unifieddev` UserDefaults domain. Not to test something, not briefly.

**Use `make dev-fast` for everyday local development.** It builds current files in debug mode,
including uncommitted edits and untracked files Git does not ignore, with a persistent cache per
checkout. Use `make dev` for committed HEAD in release mode, or `./Tools/dev-build.sh <ref>` for a
specific committed revision. Both install the same `~/Applications/Unified Dev (Dev).app`, keep its
existing dev data, and restart only the dev copy. Fast mode cannot be combined with a revision.

For agent verification without installation or launch, use
`./Tools/dev-build.sh --fast --no-install`. To install without restarting, use
`./Tools/dev-build.sh --fast --no-launch`. Restarting the dev app still needs authorisation.
See `.claude/skills/unifieddev-dev-build/SKILL.md` for the full workflow.

**Unified Dev (Dev) has its own identity:** bundle id `io.akira.unifieddev.dev`, and with it its own
preferences domain, its own saved window
state and its own notifications; its own database under `~/Library/Application Support/Unified Dev (Dev)/`
through `UD_DB_PATH` in `LSEnvironment`, and therefore its own tmux socket; its own `unifieddevdev:`
URL scheme, so it cannot swallow a `unifieddev://` link meant for the real copy. It is told apart by an
orange icon, by "Unified Dev (Dev)" in the Dock and the switcher, and by `[DEV] ` in front of every
window title. Both copies run at once.

**Open the dev copy with `open`, never by running its executable.** `LSEnvironment` is applied by
LaunchServices, so `~/Applications/Unified Dev\ Dev.app/Contents/MacOS/UnifiedDev` started by hand gets no
`UD_DB_PATH`. That used to mean it fell back to the real database and defeated every separation
above. It does not any more: with no `UD_DB_PATH`, `Store` derives the directory from
`Bundle.main.bundleIdentifier`, and only `io.akira.unifieddev` resolves to `Unified Dev`. The dev bundle id
resolves to `Unified Dev (Dev)`, which is where `make dev` points it anyway; a binary in no bundle at all,
which is `swift run` or `.build/debug/Unified Dev` and which nothing used to warn about, resolves to
`Unified Dev (unbundled)` and starts empty. Open it properly all the same, because the check at the foot
of `dev-build.sh` is worth having and because two agreeing mechanisms are the point.

**A pull request is shown in its own preview, not in the dev copy.** `make preview` builds the
worktree's current files as `.build/preview/UD #<issue>.app`, with a bundle id, database, workspaces
root and URL scheme derived from the worktree, so several run at once and none of them can reach the
real app or the dev copy. `--scenario <file>` at launch seeds the projects, scratch repositories,
workspaces and chats a test needs, inside the worktree. `make preview-clean` removes all of it, and is
part of finishing the work. `Tools/dev-build.sh` compiles under `.claude/preview.lock` in the main
checkout; opening needs no reservation. `docs/PREVIEW-APPS.md` has the rules and why they are what they are.

**`make dev-db`** copies the real database into the dev container so there is something real to look
at. It never writes back. It copies the `-wal` and `-shm` as well as `unifieddev.sqlite`, because in WAL
mode everything since the last checkpoint lives in the WAL and the main file alone is stale, and it
never opens the real database at all, because opening a WAL database writes to it. It also points
the copied workspace rows at a root that does not exist, so the dev copy can show every workspace
and cannot delete a real worktree. `--keep-paths` opts out and says why you should not.

**`make master` will refuse if you are inside the app it would replace**, because that script
removes `/Applications/UnifiedDev.app` and kills the process running from it. `Tools/guard.sh` finds the
app either as a real ancestor of this shell or, for a terminal pane whose tmux server has reparented
away, by the socket name derived from the database path. Do not work around it. Use the isolated
dev build described above instead.
