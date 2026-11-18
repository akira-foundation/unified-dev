# Preview apps, one per worktree

Every worktree can build its own copy of Unified Dev, with its own identity, its own database and
its own test state, and several of them can be open at once beside the real app and the dev copy.
This is what a pull request is shown with.

    make preview                                  build this worktree's preview
    ./Tools/dev-build.sh --preview --label "..."  the same, naming it in every window title
    open "$PWD/.build/preview/UD #31.app" --args --scenario "$PWD/Tools/scenarios/harbour.json"
    make preview-clean                            remove it and everything it made

## What a preview is

`Tools/dev-build.sh --preview` is a fast build of the worktree's current files, with the identity
applied to the finished bundle rather than to the sources. The identity is derived in
`Sources/Core/Preview/PreviewIdentity.swift` and printed for the script by the `preview` executable,
so the rule is tested in `Tests/CoreTests/PreviewIdentityTests.swift` rather than repeated in shell.

| | Derived from | Example, for `.claude/worktrees/worktree-preview-apps` on `feat/31-...` |
| --- | --- | --- |
| Bundle id | the worktree's folder name | `io.akira.unifieddev.dev.worktree-preview-apps` |
| Dock and Cmd-Tab name | the issue number at the head of the branch | `UD #31` |
| Window title | the label passed with `--label`, else the branch | `[DEV · Preview apps per worktree] Lighthouse` |
| URL scheme | the slug | `unifieddevdev-worktree-preview-apps` |
| Services menu item | the Dock name | `New UD #31 Workspace` |
| Bundle | the worktree | `.build/preview/UD #31.app` |
| Database | the worktree | `.build/preview/data/unifieddev.sqlite` |
| Workspaces root | the worktree | `.build/preview/workspaces` |
| Scratch repositories | the worktree | `.build/preview/scratch` |
| Transcript home | the worktree | `.build/preview/transcripts` |

The tmux socket, the bridge socket and the bridge token all derive from the database path, so they
separate with it. Preferences, saved window state, notifications and WebKit data derive from the
bundle id. `.build/preview/identity.env` records the identity the bundle was given, which is what
`make preview-clean` reads back.

The Dock name comes from the branch and the data from the worktree, so a worktree taken over for
another issue would build `UD #135` over the database `UD #123` seeded. `make preview` refuses
that: when the database exists and `identity.env` names another app, `preview claim` stops the
build, names both and points at `make preview-clean`.

With no issue number in the branch the Dock name falls back to `UD <slug>`. A label is cut to forty
characters, so the workspace name still shows in the title. `--label` works for the dev copy too,
and goes through the same rule.

The slug is the worktree folder's name, so two checkouts of this repository in folders of the same
name would share a bundle id. Worktrees live under one `.claude/worktrees/`, where a name is unique.

### Two agreeing paths to every location

The transcript home is where a scenario seeds the agent transcripts the spend screen counts, so a
preview never reads the owner's own 8 GB and can never write into them. `TranscriptHome` honours the
key only for a preview bundle id, refuses any path that is the owner's home or inside the directories
the CLIs keep their transcripts in, resolves symlinks before deciding, and with no key at all reads
nowhere rather than falling back to the owner's home. `PreviewLaunch.root` refuses to seed unless the
transcript home is inside the preview root, exactly as it does for the database and the workspaces.
`Tools/scenarios/agent-spend.json` seeds the week the screen is read with, its `accounts` key naming
the identity each CLI's directory holds, and
`Tools/scenarios/agent-spend-first-build.json` seeds about 175 MB instead, which is enough for a
first build to be quit in the middle and watched to carry on. `make preview-clean` removes both.

The database, the workspaces root and the preview root are written twice into `Info.plist`: under
`LSEnvironment`, which LaunchServices hands to a process it opens, and as top-level keys of the same
names. `LaunchOverride` reads the bundle's own key first and the environment only when the bundle has
none. Two cases decide that order. An executable run by hand gets no `LSEnvironment`, and without
the key it would fall back to the owner's real `~/unifieddev/workspaces.noindex` for new worktrees.
And a preview started from a terminal pane of the dev copy inherits that pane's `UD_DB_PATH`; if the
environment won, the preview would open the dev copy's database.

The real app declares none of these keys, and never takes its workspaces root from the environment
at all (`WorkspacesRoot.overrideValue`), so nothing an agent exports can move where it cuts
worktrees.

### The title is read at run time

The window title used to be marked by rewriting three Swift lines in the staged sources. It is now
one Info.plist key, `UDWindowTitlePrefix`, read by `WindowTitleMark`. The real app has no such key
and shows no mark. The dev copy and the subagents copy set it to `[DEV] ` and `[SUB] `, and a
preview to its label. Nothing in the sources changes between a dev build and a preview, so both
share the fast build cache of their worktree without recompiling anything.

## The scenario

A scenario is a JSON file describing the state a test needs. This is a shortened
`Tools/scenarios/harbour.json`:

```json
{
  "welcome": false,
  "projects": [
    {
      "name": "harbour",
      "files": { "src/pier.txt": "wood\n" },
      "commits": ["Lay the pier", "Paint the boats"],
      "remoteAhead": ["Light the lighthouse", "Ring the bell"],
      "workspaces": [
        { "name": "Lighthouse", "branch": "lighthouse",
          "chats": [{ "title": "Plan", "messages": [
            { "from": "user", "text": "Is the lamp lit?" },
            { "from": "agent", "text": "Not yet." }] }] },
        { "name": "Bell", "branch": "bell" }
      ]
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `welcome` | `false` marks onboarding complete, so the welcome window does not open. Default `true`. |
| `projects[].name` | the folder name of a scratch repository; letters, digits, `-`, `_` and `.` |
| `files` | written before the first commit, as paths inside the project |
| `commits` | the project's own history on `main`, pushed to its remote |
| `remoteAhead` | commits pushed to the remote from another clone and never fetched here |
| `branches` | branches cut from `main` with one commit each, pushed to the remote and left in the clone, open in no workspace |
| `workspaces` | cut through `WorkspaceManager.start`, as the app does, with setup skipped |
| `chats[].messages[].from` | who said it: `user`, `agent`, or `app` for a request the app sent on the owner's behalf, which is stored and not drawn. `Tools/scenarios/hidden-app-request.json` has one beside a pasted copy of the same words |
| `remote` | how the remote answers a fetch once seeding is done: `promptly` (default), `slowly`, eight seconds late, or `never` |
| `chats` | sessions in that workspace, each a list of lines |
| `agent`, `model` | on a chat, the agent and model it starts under, `claudeCode` and `opus` by default |
| `handoff` | on an `agent` line, in place of `text`: moves the chat to the `agent` and `model` it names through `Store.switchSegment`, so the divider and the first two segments are the ones a live switch writes. A return to the agent the chat started under makes a new segment, not the first one again, because the seeded segments hold no native session id to resume. The agent must differ from the one the chat runs under at that point, unless the line also names an `account`, the `label` of a declared account of that agent, which moves the chat to that account and writes the divider with the account's email, as a live switch between accounts does. `Tools/scenarios/switch-agent-in-chat.json` seeds a chat moved to Codex, one moved there and back, and one that never moved; `Tools/scenarios/switch-account-in-chat.json` seeds a chat moved from the default Claude Code account to a second one, on a project that chooses neither |
| `browser` | an address to open in a browser tab of that workspace, beside its chats |
| `question` | on an `agent` line, in place of `text`: a question card the agent asked, seeded through the same `permissionAsk` message and `permission_asks` row a live agent writes. `parts` is the list of questions on that card, each with `question`, and optionally `header`, `multiSelect`, `isSecret`, `options` (a label, or `{"label", "description"}`) and `answer`. An `answer` on every part seeds the card answered, so it draws as its closed line; an `answer` on none seeds it waiting, so the preview opens on a question to answer. Half of them answered is refused, because no card is ever answered in halves. The answer may be an option's label, several labels joined by `, ` on a `multiSelect` part, or words of the owner's own, which the closed line marks as his rather than as a listed option. A part that takes one answer and is given several labels is refused. A part marked `isSecret` is seeded with its answer kept out of the record, exactly as a live one is, so the closed line reads Hidden |
| `startedBy` | the name of a workspace of the same project, listed before this one, which started it: the row is seeded with an `agent` origin naming it as parent, the way `workspace_start` writes one, so a preview can show what an agent-started workspace may do |
| `pinned` | `true` seeds the workspace pinned, as Pin does from its menu |
| `orchestrator` | `true` seeds the workspace as its project's orchestrator, through the same `Store.setOrchestrator` the menu uses, so it is pinned and drawn first with the workspaces it started under it. A project may seed one, and never an archived one |
| `lastActive` | how many hours before the seeding that workspace was last worked in, counted back from the moment the scenario is applied. Left out, it is the seeding itself, which is what every workspace was before this key existed. It is what makes a project recent, so a scenario can show the Recent section of the project picker in an order worth reading without waiting days for one. A negative value is refused, because a preview cannot seed work done in the future |
| `archivedAgo` | how many hours before the seeding an archived workspace was archived, so a preview can show what the retention limits in Settings, Workspaces would delete without waiting for it. Only an archived workspace may have one, and a negative value is refused |
| `recordMegabytes` | adds a chat of that many megabytes to the workspace's record in the database, up to 1,000, so a size limit has something to measure |
| `unread` | `true` leaves that workspace unread once its chats are written, as a finished turn nobody has opened does, so a preview can show Ready to read without running an agent |
| `changes` | files written into that workspace's worktree once it is cut and left uncommitted, as paths inside the worktree, so the changes list, the review and the diff have something to show on first launch. The same shape as `files`; an empty string or `null` deletes the file, and deleting one the worktree does not hold fails the seeding. |
| `update` | a release the preview is offered, so the update alert can be looked at before a real release exists: `version` (the one offered), `current` (the one the preview says it is) and optionally `notes` (the release body, as GitHub would publish it). The seeded release goes through the same `SoftwareUpdate.offer` a fetched one does, and the offer appears a few seconds after launch; nothing is downloaded and Install refuses, because the release was never published. Seeding one forgets when the preview last checked and which version it had skipped, so the alert comes back on every launch with the scenario. The offered version has to be newer than the current one and not a prerelease |
| `accounts` | the agent account each CLI is signed in to, written into the preview's own transcript home so the spend screen can name a row by its email instead of by a directory. `provider` (`claudeCode` or `codex`, one default each at most), `email`, and optionally `displayName`, `organisation`, `plan` and `rateLimitTier` (`default_claude_max_20x` seeds an Ultra plan and `default_claude_max_5x` a Max one, on a `max` plan). The files written carry an identity and a plan and no credential: no access token, no refresh token and no API key, because nothing reads one and a preview should not hold one. A `label` makes it a second account beside the default, added as the app adds one, with its folder under `accounts/<provider>/<label>` in the transcript home; `missing: true` adds the row and leaves the folder out, so a project that chose it shows its account as unavailable. |
| `quotas` | usage readings stored as if the agents had reported them: `provider` (`claudeCode`, `codex` or `grok`), `window` (the key an agent uses, such as `five_hour`, `primary` or `weekly`), and optionally `label`, `hours`, `used` (a fraction, `1` is a limit reached), `resetsInMinutes`, `readMinutesAgo` (how long before launch the reading was taken, for a panel that has to say its age) and `account` (the id of the account the reading belongs to, the provider's default account when left out). A reading is drawn only under the account it was read for, so a reading seeded for one account is never shown while another is in use. A window with no `used` is one the agent named and did not measure, drawn without a figure. A preview seeded with readings stops asking the real agents for them, so they stay as written. |
| `silentAgents` | agents that answer nothing when the panel asks, so it draws them saying they did not answer, with Try again, instead of a reading. A seeded agent reports no cache of its own, so the longer reason that names when it last reported is not one a scenario can produce. Each has to be one that reports usage. A scenario naming one holds the seeded readings the same way `quotas` does, so the real agents are never asked |
| `agentsWithoutLimits` | agents that answer the panel to say plan limits do not apply to them, which is what the Claude Code CLI does when it holds no subscription credentials of its own. Each has to be one that reports usage. The panel draws the sentence whether or not the agent still has readings left to show, so a scenario may name one and seed its windows at the same time |
| `agentSettings` | what the Agents tab of the settings window shows, in place of the CLIs that tab would otherwise probe on this Mac. Only that tab and the GitHub account read it: the setup check behind the Welcome window still asks the real CLIs. `agents` lists, per agent, `agent`, `state` (`connected`, `installed` or `notInstalled`), and optionally `version` and `details`, an ordered list of `{"label", "value"}` rows such as Provider, Login method, Organization and Email. An agent the block does not name is shown as not installed, and one that is not installed carries no version or details. `github` is the account the GitHub row shows and the one a `github_username` branch prefix uses; leaving it out shows none. Without the block the real CLIs and `gh` are asked as before. It is independent of `accounts`, which names the spend screen's rows: a scenario setting both should give each agent the same email in each |
| `notifications` | what the bell in the toolbar lists: `event` (a `NotificationEvent` case), `project`, `workspace`, and optionally `chat`, `detail`, `minutesAgo` and `read`. `removed` seeds a row for a workspace that no longer exists, whose name need not be declared. A project, workspace or chat the scenario does not declare is refused |
| `profile` | the profile the project belongs to, by name: `Unified`, or one declared in `profiles`. Left out it is Unified, so a scenario that never heard of profiles is unchanged. A name the scenario does not declare is refused |
| `accounts` on a project | the account each agent of that project runs under, as `{"claudeCode": "client"}`, naming a labelled account of the scenario. Every workspace and chat of the project runs it |
| `hidden` | `true` hides the project from the sidebar, as Hide Project does. It is hidden after its workspaces are cut, because adding a workspace to a hidden project shows it again, so a hidden project may hold workspaces |
| `profiles` | profiles created before the projects are, each with `name`, `colour` (a hex string without `#`, such as `4C8DF6`) and `symbol` (an SF Symbol name), and optionally `accounts` and `github`, each `own` or `inherits`. Left out, `accounts` is `own` and `github` is `inherits`. Unified already exists and cannot be declared again; a name that folds to the same as another is refused |
| `activeProfile` | the profile the preview opens on, by name. Left out it is Unified. `Tools/scenarios/profiles.json` seeds Unified, Akira and Debtges with two projects each. It seeds a chat in every workspace but starts no agent, so an agent running in a profile that is not on screen has to be started by hand in the preview |
| `looseRepositories` | folder names of git repositories made under `scratch/loose`, with one commit each, and never added as projects, for a suggestion to point at |
| `looseFolders` | folder names made under `scratch/loose` holding one file and no repository, for a suggestion Unified Dev has to refuse to start |
| `recentFolders` | names of folders the preview opens as if they had been opened recently, newest first, written to `directories.recent` so the Start a Project card has a list to draw. Each has to be a project, a `looseRepositories` or a `looseFolders` entry of the same scenario; a name it never makes is refused rather than seeded as a path that is not there |
| `suggestions` | cards seeded into that chat after its lines, through the same `Store.addWorkSuggestion` the bridge uses. Each has `title`, `why` and `prompt`, and at most one of `project` (another project of the scenario, or `owner/repository` on GitHub), `looseRepository` or `looseFolder`; with none of them it is work in the same project. `state` is `pending` (the default), `started`, `dismissed` or `withdrawn`, and a `started` card names the workspace of the same project it started in with `startedIn`. At most five may wait in one workspace |

`Tools/scenarios/suggested-work.json` seeds one card of every kind in the Import chat of `lantern`:
work in the same project, in the hidden `almanac` (starting it shows the project again), in the
loose repository `tidewater` (offered as Add Project and Start), in the loose folder `driftwood`
(refused, because it is not a repository), and on GitHub; then one started in the `Lamp` workspace,
one dismissed and one withdrawn, so every record a card can end as is on screen. Five cards wait, so
the Importer row carries the sidebar mark. A card started with Here runs as a subagent, which
appears under its chat in the sidebar.

`Tools/scenarios/suggested-work-from-github.json` seeds cards aimed at GitHub: one waiting for
`octo/parsekit`, one waiting for `octo/tidereader` and one for `octo/parsekit` already dismissed,
beside the loose repositories `parsekit` and `parsekit-mirror`. A scenario gives a loose repository
no remote, so the tester sets them before adding either:
`git remote add origin git@github.com:Octo/ParseKit.git` in `parsekit` and
`git remote add origin git@gitlab.com:octo/parsekit.git` in `parsekit-mirror`. Adding
`parsekit-mirror` changes no card. Adding `parsekit` turns the waiting `octo/parsekit` card into
work in that project, offered as New Workspace, and leaves the other two as they were.

**A scenario cannot start a server, and one that opens a page of its own needs the tester to.**
`browser` is an address and nothing else: `PreviewScenarioSeeder` writes a browser tab pointing at
it and no scenario field runs a process. Two of the three browser scenarios dodge this by pointing
at `https://example.com/`, which the machine can fetch. `Tools/scenarios/browser-agent-acts.json`
cannot, because the five acting tools need a form to act on and a public page changes underneath
whoever is testing, so it writes `form.html` into the `harbour` project and points the tab at
`http://127.0.0.1:8111/form.html`. Nothing listens there until somebody starts it, **after** the app
has launched and seeded, because the directory does not exist before that:

```bash
(cd "$PWD/.build/preview/scratch/projects/harbour" && python3 -m http.server 8111)
```

It holds that terminal, and Ctrl+C ends it. Without it the pane draws Unified Dev's failed-load card
and `browser_snapshot` answers that there is nothing on the page to point at, which is the honest
answer and not the one the walkthrough is for. `PaneOrder.parse` takes only `http` and `https`, so
`file:///` is not a way round it.

`Tools/scenarios/answered-questions.json` seeds the Decisions chat of `lantern` with one card of
every state a question can be in: one answered with a listed option, one answered in the owner's own
words, one of three parts answered whole, one secret, and one still waiting. The answered ones draw
as their closed line and reopen with the choice marked; the waiting one closes as it is answered.

`Tools/scenarios/welcome-blocking-check.json` seeds one project and leaves the Welcome window to
open on its own, since nothing marks onboarding complete. A scenario cannot say what the setup
check finds, so the checks come from `--setup-rehearsal no-agent` at the same launch: every agent
missing, which blocks, and the GitHub CLI missing, which does not. The checks step opens straight
onto the Claude Code install, and the GitHub CLI's row and its detail both read optional.

`Tools/scenarios/unbounded-height.json` seeds `lantern` with the state
`Tools/unbounded-height-probe.sh` reads: one workspace whose name and whose waiting question both
carry a sentence long enough to wrap in any column, and a second holding the same question with
options that cannot wrap, which is the control the first is compared against. The names are
deliberately unreadable; a scenario that made them comfortable would not make anything wrap.

`Tools/scenarios/toolbar-band.json` seeds `breakwater` with one workspace of one chat, one of three
chats and one with sixty changed files, the cases to compare the top of the window in. Launched with
`--toolbar-band-probe <file>`, the preview writes to that file what the toolbar's background views
measure for each combination of workspace, window mode and tab bar it sees, and the whole tree of views
at the top of the window once per mode. It selects nothing: moving between the workspaces and entering
full screen is left to whoever is at the Mac, and a state nobody reaches is not in the report.

`--scenario <file>` at launch reads it. `PreviewScenarioLaunch` reads and validates it before any
window opens, then `AppModel.bootstrap` seeds it through `PreviewScenarioSeeder` in the core, once
the store is open and before the sidebar loads. Every repository is made with the app's own `Git`,
every row with its own `Store` and `WorkspaceManager`: no SQL is written by hand. Each project gets a
bare remote under `scratch/remotes` and a clone under `scratch/projects`, committed with a fixed
scratch author and with signing and hooks turned off, so the owner's own git configuration never
touches a scratch commit.

It refuses, and creates nothing, when:

- the process is not a preview: the bundle id must be `io.akira.unifieddev.dev.<slug>`, and the
  database and workspaces root must both lie inside the preview root (`PreviewLaunch.root`). The real
  app and the dev copy can be given `--scenario` and do nothing but say so;
- the path is relative: an app opened with `open` starts in `/`, so the scenario is always given as
  an absolute path;
- the scenario is invalid: a suggestion naming a project, loose folder or workspace the scenario does
  not make, or more than five waiting in one workspace, a project name with a slash, a file or change path leaving the project or naming
  `.git` in any case, a branch git would refuse, `main` as a workspace branch, a branch nested under
  another (`ui` and `ui/panel`), or a name used twice;
- the preview already holds a project. A scenario seeds an empty preview once; launching again
  leaves the state the tester has made since, and a notice that stays until it is dismissed names
  the scenario that was not applied and the projects that are there. `make preview-clean` starts
  over.

A failure part way through, a push refused for instance, leaves what was made so far and says so
in an alert; the next launch sees projects and seeds nothing more. `make preview-clean`, a new build
and a new launch are the way back.

`open` passes `--args` only to an app it is launching, so quit the preview before opening it again
with a scenario. Do not add `-n`: it starts a second instance of the same preview on the same
database.

## Photographing a preview

`--snapshot-window <file.png>` writes a PNG of the window and exits.

    --snapshot-window <file>   where to write the PNG
    --offscreen                keep the window invisible until the moment of the shot
    --background-capture       never activate the app
    --window-size 1600x1000    the content size, in points
    --window-wait 150          how long to wait for the window, in seconds
    --select <workspace id>    which workspace to open first
    --appearance light|dark    which appearance to draw
    --capture-delay <seconds>  how long to settle before shooting
    --stage <name>             what to arrange before shooting

The same flag already took `--new-workspace`, `--new-project`, `--project-setup`, `--settings`
with `--settings-tab`, `--repo-settings`, `--about`, `--welcome` and `--sidebar-width`, and still
does. `--stage` is beside them, not instead of them.

### The stages

`window` (the default), `create-workspace`, `review`, `agent-choice`, `terminal`, `browser` and
`spend`.
`CaptureStage` in the core reads the name, so an unknown one is refused by name and `--stage` with
nothing after it is refused rather than ignored.

**Every stage but `window` runs in a preview and nowhere else.** Arranging the app means
discarding the drafts that would otherwise sit in the shot, writing `inspector.diffSideBySide`,
opening a review tab and starting a shell, and none of that may happen to the owner's own copy. The
refusal is `PreviewLaunch.root()`, the same check the scenario seeder passes, so the bundle id must
be a preview's and the database, workspaces root and transcript home must all lie inside the
preview root. `--snapshot-window` on its own still only photographs, wherever it is run.

`browser` selects the workspace's chat, splits it, and puts a browser pane beside it, the way
`ResizeProbe` and `ComposerProbe` already do. It refuses by name when the workspace has no chat to
split or when the pane does not arrive, rather than photographing a window without one. The page is
`https://example.com/` unless `--browser-url` names another, and it is fetched over the network
into the preview's own WebKit store, so this is the one stage that reaches off the machine. The
split is remembered in the preview's preferences, so clear that domain before shooting it twice or
the second shot has two browser panes.

`Tools/scenarios/landing.json` is the scenario the stages were written against: three projects,
workspaces with changes, unread turns and none, a conversation of nine messages, and six days of
agent spend. `--settings`, `--repo-settings` and the `spend` stage each wait for the window they asked for by
its scene identifier rather than for whatever window is not the main one, because a window left
over from an earlier run is otherwise photographed instead. `SecondWindow` in the core decides
which window a run is waiting for, so the wait and the opening cannot disagree, and `WindowScene`
decides whether an identifier names a scene: `repo-settings` does not answer for `settings`.
`--about` and `--welcome` have no scene of their own, so those two still take the first window that
is not the main one.

A workspace id for `--select` comes out of the preview's own database once it has seeded:

```bash
sqlite3 .build/preview/data/unifieddev.sqlite "select id, name from workspaces"
```

### What the capture reads, and where the window is

Both ScreenCaptureKit reads list windows through `SCShareableContent.currentProcess`, so only this
process's own windows can be composited; nothing of the owner's screen can reach the file.

`create-workspace` and `agent-choice` open a popover, which is a window of its own that a
single-window capture leaves out. Those two are shot through one filter over the display, with this
process's own windows named in it, and `WindowComposite` works out the rectangle the window and its
popovers cover, clipped to the screen they are drawn on. A filter over the display can only read
what is on the display, so **those two stages keep the window on the screen** and the other four
never take that path: a window parked off the screen is always shot on its own, through the
window filter, which does not care where it is.

`--offscreen` is what decides whether any of that hiding happens. With it, every window opens at
`alpha = 0` and is raised for the moment of the capture; the stages that are not shot with a
popover are also moved to -30000,-30000 first, which macOS allows only as far as leaving a corner
of about 40 by 97 points on the screen. Without `--offscreen` the window sits visible throughout,
which is what you want when you are watching it and not what you want on somebody's working Mac.

A window wider or taller than the screen cannot be shot whole through the display filter, so a
popover stage shrinks it to fit first. The shot is then smaller than `--window-size` asked for.

When the window filter fails, there are two more paths, in this order: `/usr/sbin/screencapture -l`
on the window's own id, which is a separate binary and does consume the screen recording grant, and
an in-process draw of the view tree, which says so on stderr and omits the AppKit panes. Neither is
reached for a stage shot with a popover.

`--capture-delay` is spent before the stage is arranged, not after, so it is time for the app to
settle rather than time for the arrangement to settle. Each stage waits for its own work on top of
it. `--window-wait` is how long the capture waits for a window to exist at all, ten seconds by
default.

Every capture dismisses the GitHub refresh notice on every workspace, because a scratch remote is
not a GitHub repository and the failure is noise in a photograph. It is held in memory for the few
seconds the capture process lives and written nowhere.

## One build at a time, any number open

Compiling is what the machine cannot afford twice. `Tools/dev-build.sh` takes a reservation in the
main checkout's `.claude/preview.lock`, in every one of its modes. A fast build or a preview releases
it once compiled; a release build holds it to the end, because it shares `/tmp/unifieddev-dev-src`
and `/tmp/unifieddev-dev-build` with every other release build. The file names the pid, the
worktree, the branch and the start time. A reservation whose pid has gone is taken over, by moving
it aside and checking it is still the one that was read; one written by hand with no pid is left
alone and reported, because the rule before this one was a reservation held until the owner had
finished looking. `subagents-build.sh`, `master.sh` and `make app` do not take it.

Opening needs no reservation. Every preview open with agents running adds its processes to the
machine, so say so when handing over a second or third.

## Cleaning up

`make preview-clean` quits the preview if it is running, kills its tmux server by socket name,
removes its bridge socket, unregisters the bundle from LaunchServices, deletes its preferences
domain, its saved window state, caches, HTTP storage, WebKit data and fallback Application Support
folder, removes `.build/preview` (the bundle, the database, the scratch repositories and every
workspace the scenario or the tester cut there) and the worktree's fast build cache under
`/tmp/unifieddev-dev-fast-<hash>`.

Every path it removes is either inside `.build/preview` of the worktree it runs in, or under
`~/Library` named by a bundle id that `ud_refuse_unless_preview` has already checked is a preview
identity. It refuses to run from inside the preview it would remove, and it refuses an `identity.env` whose
bundle id was not derived from this worktree's name or whose bridge server name is not the one that
bundle id gives, so a stale or edited file cannot point it at another preview or at the real app's
registration.

## Decisions, and what they were measured against

### The user-level bridge registration

`BridgeRegistration.ownerServerName` names the entry in `~/.claude.json` after the bundle id, so the
real app's is `unified-dev`, the dev copy's `unified-dev-dev`, and a preview's
`unified-dev-io-akira-unifieddev-dev-<slug>`. On the owner's Mac on 18 September 2026 the top-level
`mcpServers` table held none of them.

The app never writes a registration on its own. The only write is
`BridgeUserRegistrationRepair`, which rewrites an entry under this copy's own name, carrying this
copy's own socket and token, whose shim has moved. A preview therefore cannot rewrite the real
app's entry or another preview's: different name, and a socket and token no other copy can mint.
`Tests/CoreTests/BridgeUserRegistrationRepairTests.swift` holds that with two previews and the real
app in one file.

So several previews do not fight over the registration, and none can point the owner's `claude`
at itself unless the owner pastes the command a preview offers. If that happens, the entry is
under the preview's own name and `make preview-clean` removes it from Claude Code, Codex and Grok,
because a registration whose shim has been deleted fails in every session that loads it.

### The URL scheme

LaunchServices binds a scheme to whichever registered bundle it prefers, and on the owner's Mac
`unifieddevdev` was bound to the dev copy alone. Every preview sharing it would have let a link meant
for the dev copy open in whichever preview registered last. Each preview gets
`unifieddevdev-<slug>`; `DeepLink` accepts whatever schemes its own bundle declares, so nothing in the
app changed for it. The Services menu entry and its port name are per preview for the same reason.

### Keeping the real app and data out of reach

`Tools/guard.sh` gained `ud_refuse_unless_preview`, run on the identity before anything is
installed and before anything is removed. It refuses a bundle id that is not
`io.akira.unifieddev.dev.` followed by a lowercase slug, which excludes the real, dev and subagents
ids by construction; a root other than this worktree's `.build/preview`; a bundle, database,
workspaces root or scratch root outside that root or climbing out of it with `..`; and a database
inside the real, dev or subagents Application Support folders. `ud_refuse_real_app`,
`ud_refuse_real_db` and `ud_refuse_if_own_host` still run on top of it.

### The third identity

`Unified Dev Subagents` stays as it is, a fixed identity installed to `~/Applications`. A preview
generalises it: the same separation, derived per worktree instead of written into a script, and
living inside the worktree instead of beside the owner's apps.

---

[Architecture](ARCHITECTURE.md) · [Bridge](BRIDGE.md) · [Agents integration](AGENTS-INTEGRATION.md)
