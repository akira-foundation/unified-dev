# Profiles

A profile is a named group of projects. The window shows one profile at a time: its projects, their
workspaces, Home and the archive. Someone who works for several organisations keeps each in its own
profile and switches between them without the others in the way.

Every profile has a name, a colour, a symbol, a position in the list and a folder. The first one,
Unified, exists from the start, has the fixed id `unified`, and cannot be deleted. Every project
belongs to exactly one profile. A database that predates profiles has every project in Unified.

## Folders

A workspace is a worktree on disk, and a profile gives its worktrees a folder of their own:

    <workspaces root>/<profile folder>/<project>/<branch>

The folder is derived from the profile's name when the profile is created and never changes
afterwards, so renaming a profile does not move anything. Accents and case are folded and anything
that is not a letter or a digit becomes a dash, so "Débtges" gives `debtges`. Two names that fold to
the same folder get different ones, the second ending in `-2`. `ProfileFolder` decides it.

The initial profile's folder is `unified`: its new worktrees are created under `unified/`. Worktrees
that already existed before profiles are never moved and stay where they were.

A folder never resolves into the directory of a project from before profiles, which holds its
worktrees directly as `<workspaces root>/<project>/<branch>`. When a profile's folder is one of those
directories, recorded or found on disk, its new worktrees go under the same name ending in `-2`, or
the next number free, for as long as that directory holds a checkout or a workspace still records
it. The profile's own folder does not change, and neither do worktrees that already exist. Folder names are compared ignoring case, as the
disk does.

## Accounts

Every agent account belongs to one profile. Settings, Agents lists the accounts of the active
profile, and an account added there belongs to it, or to Unified when the active profile uses
Unified's. Profile Settings signs in to an account of the profile it is editing, whichever
profile the window shows, and a profile that has just taken accounts of its own, new or switched,
stays open after Save to sign in to the first one. The id of an account stays global and carries its
provider, so the same login wanted in two profiles is two accounts, each signed in on its own.

A profile either has accounts of its own or uses the accounts of Unified, never both. It is chosen
when the profile is created, and changed in Profile Settings. A new profile uses Unified's until it
is told otherwise. Using Unified's means all of them and Unified's default, as they are now and as
they change, with nothing copied. Unified always has its own.

Each profile with accounts of its own has a default per CLI, chosen in Profile Settings among them.
The login this Mac already had, `~/.claude` and `~/.codex`, belongs to Unified.

Which account an agent runs under is decided in this order:

1. the account chosen for the project, among those of its profile;
2. the default of the profile, or of Unified when the profile uses Unified's;
3. this Mac's own login, for Unified and for a profile that uses Unified's.

A profile with accounts of its own never takes the third step, for a CLI that has a default account
to fall back to. When neither the project nor the profile names an account for the CLI that is still
there, the turn does not start: the chat says why and asks for an account, and the composer and
Settings show the account as unavailable before anything is sent. A CLI that has no default account
at all is the exception, and Grok is the one today: there is nothing to refuse the fall back to, so
the turn runs under this Mac's own login in every profile, and Settings says so rather than
promising a refusal that would not happen. The work of one organisation therefore
cannot run, or be billed, under the login of another. A project of such a profile that holds a
choice of this Mac's own login, made on purpose, runs it. `ProfileAccounts` decides what a profile
holds, lists and reaches, and `AgentAccountLaunch` decides whether a choice may start an agent at all.

An Ask chat has no project, so it skips the first step and runs the default of the profile its turn
is pinned to, which is the active profile when the turn starts (see [The bridge](#the-bridge)). Its
composer has no Account row, because there is no project whose choice it could change.
`AccountScope.chat` decides which scope a chat's turns run under.

Changing a profile's default does not stop a turn. The chat moves to the new account on its next
send, with the notice and the divider of [CHAT-SEGMENTS.md](CHAT-SEGMENTS.md). A CLI already running
in a terminal pane keeps the account it was started with until the pane is closed.

### When something moves

A project moved to another profile keeps no choice of an account its new profile does not hold: the
choice is cleared, the project runs the new profile's default, and a notice names what changed. A
profile that switches between its own accounts and Unified's clears the same way, for every project
in it, and switching back does not bring those choices back. While a profile uses Unified's, the
accounts it owns are listed nowhere and wait for it to have its own again. Deleting a profile, which
by then has no projects, gives its accounts back to Unified.

Removing an account is refused while an agent runs under it, counting the agents that reach it as
their profile's default, those whose project chose it and chats recorded on it, in archived workspaces
as well. For a folder inside the accounts root it is also refused while any process
of this user names the folder in its arguments or environment, and when Unified Dev cannot
read a process to tell; a folder outside that root is never deleted, so its row can always go. The confirmation names the projects
that chose it; they go back to their profile's default, and in a profile with accounts of its own and
no default for that CLI they do not start until another is chosen.

### A database from before

The migration is additive. Each existing account goes to the profile whose projects chose it, and to
Unified when no project chose it or projects of more than one profile did. A profile that receives
no account uses Unified's, so its agents run exactly as they did; one that receives an account has
accounts of its own. A project of such a profile that chose an account left with Unified, because
another profile's projects chose it too, loses that choice and runs its profile's default, with the
warning the composer shows for a lost choice, or does not start until an account is chosen when the
profile has no default for that CLI.

### Spend and quotas

The spend screen shows the active profile: the turns run in its projects, and the lines of its
accounts and of this Mac's own login. Turns run outside every project are Unified's. The quotas in the menu bar panel are those
of the account the active profile runs, for the selected workspace or, on Home, for the profile's
default.

## GitHub

Every `gh` call Unified Dev makes for a project, and every agent and terminal a workspace starts, runs
under the GitHub login of the project's profile. Profile Settings has a GitHub section for it.

A profile either uses Unified's GitHub login or has its own, chosen in that section. A new profile uses
Unified's until it is told otherwise, and Unified's is this Mac's own `gh` login, in `~/.config/gh`.
Unified always uses it. The section says which login the profile uses and who it is signed in as.

A profile with its own login keeps it in a folder of its own, `GitHubLogins/<profile id>` beside the
database, which Unified Dev creates when the profile first signs in, readable by this user alone. Signing in
runs `gh auth login --insecure-storage` in the section's sheet with `GH_CONFIG_DIR` set to that folder, so
the token is written to `hosts.yml` in the folder and never to the login Keychain. That is deliberate: `gh`
keeps one Keychain entry per host for the active login whatever `GH_CONFIG_DIR` says, so a profile signing in
there would replace this Mac's own login, and a profile with nobody signed in would read this Mac's token
back from it. Unified Dev never signs out on its own.

A profile with its own login and nobody signed in does not fall back to this Mac's login. Unified Dev sets
`GH_TOKEN` to a value GitHub refuses whenever the folder holds no token for github.com, and
`GH_ENTERPRISE_TOKEN` likewise when it holds none for another host, which `gh` prefers to the Keychain,
so its pull requests, checks, agents and git credentials stop at GitHub and ask for a sign in, and the work of
one organisation cannot run under the identity of another. Switching back to Unified's login keeps the folder, and switching to
its own again finds the same login. Deleting a profile leaves its folder, and the token in it, where they are.

`GitHubLoginRoutes` decides which profile a directory belongs to, from the projects and workspaces that hold
it, as written first and then through any symbolic link, ignoring case on a disk that ignores it, and `ProfileGitHubLogins` decides which login
that profile uses. A directory no project holds runs under this Mac's login. When the database cannot be read
to tell, and some profile has a login of its own, the call runs signed out rather than under this Mac's login.
A workspace chat's agent runs under the login of its project's profile, and an Ask chat's under that of the
profile its turn is pinned to. The app sets `GH_CONFIG_DIR` for the profile's login and clears `GH_TOKEN`, `GITHUB_TOKEN`,
`GH_ENTERPRISE_TOKEN` and `GITHUB_ENTERPRISE_TOKEN`, which `gh` would otherwise prefer to the folder, except
for the refused values of a profile nobody has signed in to.
Agents get them when their process starts, and terminals when their shell or tmux session starts, so a
running one keeps the login it started with. Creating a repository from Add Project runs under the active
profile's login, and filing feedback about Unified Dev itself runs under this Mac's.

The `git` commands Unified Dev runs against a remote get the same variables: push, fetch, clone,
`ls-remote`, `remote prune` and submodule updates. A sign in is refused when Unified Dev cannot tell which
profile a directory belongs to, so nobody signs in to a login no profile owns. A `git push`,
by Unified Dev or by an agent, uses the profile's login only when git asks `gh` for credentials, which is what
`gh auth setup-git` configures. With the macOS Keychain helper, or an SSH remote, git pushes with whatever
those hold, whichever profile the project is in. The default branch prefix taken from the GitHub user name
is read from this Mac's login.

## Bitbucket

A profile's Bitbucket sign-in follows its GitHub choice: a profile using Unified's GitHub login uses this
Mac's `bkt` configuration and Keychain, and a profile with its own GitHub login has its own Bitbucket one,
in `BitbucketLogins/<profile id>` beside `GitHubLogins/`. bkt keys its Keychain item by host alone, so the
profile's token lives in bkt's encrypted file store in that folder instead. Profile Settings shows it in a
Bitbucket section, with the browser and an API token as the two ways to sign in. `docs/BITBUCKET.md` has
the variables and why.

## Moving a project

Project menu, Move to Profile, in the sidebar and on Home. Only the project's row changes. Its
existing worktrees stay on disk exactly where they are, and the workspaces keep working. A workspace
created afterwards is placed under the folder of the profile the project is in then, so after moving
a project into Debtges its next workspace is created under `debtges/`.

A profile that still holds projects cannot be deleted: the projects are moved first. What a move
does to the project's account is under [Accounts](#accounts).

A moved project's agents keep running, but they now belong to the new profile. `workspace_say` and
`workspace_archive` no longer reach their siblings in other projects of the old profile, in either
direction. A `notify_when_done` asked for before the move still arrives.

## Switching

The switcher is a menu in the title bar, to the left of the button that shows and hides the sidebar.
With the sidebar open it shows the profile's mark and name. The sidebar cannot be dragged narrower
than the width that holds the traffic lights, the switcher with its mark and whole name, and the
sidebar toggle, nor narrower than the footer needs to keep New workspace labelled. A long name is cut
with an ellipsis inside a menu of capped width, so it cannot push that minimum up without bound.
`ProfileToolbarLabel` and `WindowWidths.holding(sidebarContent:)` decide it. With the sidebar hidden, and
in full screen while the bar is hidden, it shows the mark alone and still opens. The mark alone sits on
glass, like the button beside it. Revealing the bar in full screen brings the name back. The help tag
and the accessibility label carry the whole name.
The Profile menu lists the profiles too, with New Profile and Profile Settings.

| Key | Action |
| --- | --- |
| `⌃⌘1` to `⌃⌘9` | Switch to the profile at that position |

The search palette reaches them too: from two typed letters, under Everything, it lists the profiles
whose name matches, best match first, and picking one switches to it. The section comes before the
workspaces when its best match is at least as good as theirs. The active profile is not listed, and
the workspaces and transcripts it finds stay those of the active profile. `SearchPanelProfiles` decides it.

`⌘` and a digit stays with the tabs. The active profile is stored and restored at launch, and each
profile remembers its last workspace. A stored active profile that no longer exists opens Unified, on
Unified's remembered workspace, or on Home when it has none. A remembered workspace that was archived
lands on the active profile's Home.

Switching changes what is shown and nothing else. It does not stop, close or restart any agent or
terminal. An agent working in a profile that is not on screen keeps working, still counts towards
keeping the Mac awake, and a notification from it names its profile so it is clear where it came
from.

## The bell

The bell in the window toolbar lists notifications from every profile, newest first, and shows how
many are unseen. Its toolbar item is titled Notifications, with the unseen count, so the overflow
menu, VoiceOver and the toolbar's customisation sheet can name it. The popover sizes to what it lists:
short with a centred empty state when there is nothing, and scrolling under a fixed header past a
maximum height. Mark All as Read is offered only while something is unseen. Each row carries its profile's mark and name. Clicking one switches profile when it
has to and opens the workspace and the chat it was about, and a macOS banner goes to the same place.

It records turns finishing, an agent that needs something, an agent that stops, a setup script that
fails, checks finishing on a pull request and a usage limit being reached. The switches in Settings,
Notifications govern banners only, so the bell records whatever they say, and it stays quiet only
for what is already on screen while the app is in front.

A row stops counting when its chat is opened by any route, or through Mark All as Read, and stays in
the list, dimmed, until it expires after 7 days or falls past the newest 200. A row whose workspace
was archived opens the archive view. One whose workspace was removed stops counting, says so and does
not open. One whose chat was deleted opens its workspace with a notice. A project moved to another
profile takes its rows with it. `NotificationInbox` and `InboxNotification` decide all of this.

## The bridge

An agent calling back in through the bridge sees only its own profile: the projects, workspaces and
chats of the profile its workspace belongs to. The owner's client sees the active profile. An Ask chat
is pinned to the profile active when its turn starts, for that turn, so switching mid turn does not move
what it is doing. While that turn belongs to a profile the window is not showing, `reveal` is refused,
names the profile, and leaves the window where it is. Anything in another profile is answered as if it did not exist, unless the caller may reach it. `workspace_start` and
`project_add` name the profile they landed in. The scope and its exceptions are in
[BRIDGE.md](BRIDGE.md), under "The profile a caller is limited to".

### Connected to other profiles

Profile Settings carries a switch, **Connected to other profiles**, off by default. Turned on, whatever
comes from outside the profile goes through the orchestrator of the project it is for. Any workspace,
subagents included, can list that profile's projects and their orchestrators and send one of those
orchestrators a message, if its own profile is on too and its chat, on Claude Code, was launched in Accept
edits, where the owner approves every such call; a chat launched in any other mode is told it cannot. A message to
another of its workspaces is refused and pointed at the orchestrator. A project's orchestrator can also
read the profile's chats and changes and write to any of its workspaces, and an ordinary workspace that
needs to read there asks that orchestrator instead. The owner's Ask chat and client need only the
destination on. A chat on Codex never crosses.

A message for a project with no orchestrator becomes a card for the owner, carrying the message, and only
the owner's click starts an orchestrator there and delivers it. A message to a profile that is off is told
so plainly. Nothing else can be started in another profile.

Every crossing names the profile, through a `profile` argument, or `all` on the two lists. A message
from another profile says where it came from and does not carry the owner's authority, whoever sent it. The
turn it wakes runs on the destination project's account. A chat cannot be answered across profiles except by
a caller that may cross, so what comes back to anyone else is the end of that turn, if `notify_when_done`
asked for it. [BRIDGE.md](BRIDGE.md) has the rules, under "Reaching another profile".

## In a preview scenario

A scenario may declare `profiles` (`name`, `colour` as a hex string without `#`, `symbol`, and
`accounts` and `github`, each `own` or `inherits`), name one for a project with `profile`, and open on one with
`activeProfile`. A labelled account that names a `profile` is added to it, and `isProfileDefault` makes
it that profile's default; a labelled account that names none belongs to Unified, and the one with no
label is this Mac's own login, which cannot name a profile. A project that names no profile
is in Unified. `reachableProfiles` names the profiles to open to the others, and
`Tools/scenarios/profiles-reach.json` seeds an orchestrator in Unified with Akira open and Debtges closed.
`Tools/scenarios/profiles.json` seeds Unified, Akira and Debtges with two projects
each, Akira with two Claude Code accounts and a Codex one of its own and Debtges using Unified's, and
Akira with a GitHub login of its own, signed out until someone signs in, and Debtges using Unified's. A
scenario may also declare `notifications` for the bell (`event`, `project`, `workspace`, optional
`chat`, `detail`, `minutesAgo` and `read`, and `removed` for a workspace that no longer exists). See [PREVIEW-APPS.md](PREVIEW-APPS.md).

## Not there yet

- The oceans chart is global: it shows every profile's.
- Moving a project's existing worktrees into its new profile's folder.
