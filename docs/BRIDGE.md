# The Unified Dev bridge

What an agent can ask Unified Dev to do, and which callers may ask for what. The other direction from
`AGENTS-INTEGRATION.md`, which is about Unified Dev reading what the CLIs put on disk; this is the CLIs
calling back in.

Everything here is read off `Sources/Core/Bridge/`, which is where all of it lives. The heads
of the files named below carry the reasoning at length, and this is the map over them.

Related: `AGENTS-INTEGRATION.md` (registering Unified Dev in a client the owner runs themselves),
`PROTOCOL.md` (Claude Code's stream-json), `CODEX.md` (Codex's app-server).

---

## 1. Why there is a shim at all

Unified Dev serves MCP over a unix domain socket. Neither CLI can speak to one: Claude Code registers an
MCP server as a stdio command or an HTTP URL, Codex as a stdio `command` or a streamable HTTP
`--url`, and that is the whole list on both. HTTP on localhost was refused for a different reason,
which is that it would be one port for the whole machine, reachable by every local process, and
impossible to share between Unified Dev and Unified Dev (Dev), a pair that is a documented permanent arrangement
rather than a test setup.

So the registered transport is stdio and the socket sits behind it. `bridge` is the stdio
process the CLI launches, shipped inside Unified Dev's own bundle, and it is a line relay and
deliberately not an MCP implementation:

```
agent CLI  ──stdio──▶  bridge  ──unix socket──▶  Unified Dev
```

**Every behaviour that lives in the shim is a behaviour that can skew against the app.** Installing a new build
replaces the bundle underneath a running Unified Dev and the CLI launches whatever binary the path in its
config names, so a shim that knew anything about tools could be a version behind the app it is
talking to. A relay changes almost never; the tool surface changes every time a tool is added. So
`initialize`, `tools/list` and `tools/call` are all answered in the app, in `BridgeDispatch`, where
the store is reachable.

The shim sends one hello line before any MCP byte crosses, carrying a protocol version, the token
and the claimed role, and Unified Dev answers with one welcome line that accepts or refuses. The version
is compared for **equality and never as a range**, because the skew to design for is a new shim
meeting an older running Unified Dev after a new build replaced the bundle mid-session. Both directions have
to fail with a sentence rather than hang: a hung tool call is a hung turn, and a model cannot tell
one from the other. See `BridgeProtocol` and `BridgeShim`.

The shim exits with distinct statuses because the CLI prints them, and "exited 1" says nothing that
"Unified Dev is not running" does not say better: `64` nothing to connect to, `69` could not reach Unified Dev
or Unified Dev went away mid-answer, `70` refused at the handshake.

## 2. Who is calling, and how Unified Dev knows

Two roles, in `BridgeIdentity.swift`.

| Role | What it is | What it is scoped to |
| --- | --- | --- |
| `workspace` | An agent running in a workspace, whoever created that workspace | Its own worktree, implicitly |
| `owner` | The owner, through a client of their own, sitting in no workspace | Nothing implicitly. Everything is named out loud |

**The role is decided by Unified Dev at mint time, never read from the shim's environment.** The
environment carries a claimed role, and it is carried for diagnostics only: anything running as the
user can launch the shim by hand with any role it likes, so a claim that disagrees with the token
is worth a log line and nothing else. A session token is always `workspace`; the standalone token
is always `owner`. A shim from an older build still says `parent` or `child`, and is served by its
token all the same.

**There used to be a third, `child`, and it went because it cost more than it protected.** A
workspace another agent had started could call `whoami` and `workspace_say` and nothing else, on
the argument that nobody had weighed that agent. In use it could not archive or rename itself when
the workspace that started it asked it to, could not read the chat it was answering, and could not
open a terminal in its own worktree. The pen was not holding either: the owner's own registration
of the bridge, which Claude Code applies to every session on the machine, handed that same agent
the owner's tools through a second shim (see "The owner's token inside a worktree" below). What
stops a runaway agent never needed a role: a workspace an agent started may not call
`workspace_start`, checked in the handler off its row; anything destructive asks; archiving runs
its safety checks with nothing forced.

The nesting limit is still one, and still a column rather than a counter: a workspace whose row
names a parent was started by an agent, and that is the whole test. "Has a parent" **is** the
depth, and a number kept beside it is a number that can drift. "Parent" in the rest of this
document means only that, the workspace that started another, and never a role.

`owner` is the odd one. `workspace` is derived from a workspace row and this one is derived from
nothing: no session, no worktree, no project. **It is not a workspace**, because every tool a
workspace agent has is implicitly scoped to the worktree it is sitting in and this caller is
sitting in none.

**Two clients come in on it, and neither is a special case of the other.** One is the owner's own
terminal, holding the token the welcome window's command line step or Settings > Command Line handed
them. The other is Ask Unified Dev, the conversation inside the app that belongs to no workspace:
`BridgeServer.register(askSession:)` mints it a token of its own for each chat, in memory like a
workspace's, carrying the role `owner` and the chat it speaks for, because a card that
`work_suggest` puts in a chat needs to know which chat that is. The definition above is still
exactly what that chat is, so every tool answers it as it answers the owner. The standalone token
stays the revocation: regenerating it from Settings retires every Ask chat's token with it, and the
chat is given a new one the next time its agent starts.

Because that token names the chat, **a workspace an Ask chat starts takes that chat's controls**:
its model, its agent and its permission mode, whether it is started with `workspace_start` or from a
card the chat suggested. An Ask chat running with permissions bypassed starts workspaces that run
the same way. The owner's own terminal names no chat, so what it starts takes the defaults.

Identity is minted by Unified Dev and handed to the CLI through the shim's environment, never claimed by
the agent. That is what lets a tool be implicitly scoped: **a workspace agent naming nothing is
acting on the workspace its token names**, so there is nothing for a model to forge, mistype or
hold on to after it has gone stale. The owner's own client is the exception and has to be, because
it is sitting in no workspace: `reveal`, `workspace_merge` and `workspace_rename` are named a
workspace out loud, resolved against the rows that exist, and refused when a name is shared by two
of them.

**Two tools do take a workspace from a workspace agent, and both are narrowed to the same set.**
`workspace_rename` and `workspace_archive` act on the caller's own when nothing is named, and may
name only a workspace the caller started; any other is refused rather than quietly read as its own,
and naming the caller's own id is answered by saying to leave the argument out. Which workspaces it
started is read off `WorkspaceOrigin.parentWorkspaceID`, written once when the start happened, so
what the model can reach is still decided by a column rather than by the argument. They differ in
one way, because what they act on differs: a rename is one column and takes a name or an id, while
an archive removes a worktree and takes the exact id `workspace_start` reported, so a slip of the
name cannot cost anything.

**The three readers take any active workspace in the caller's profile.** `chat_list`, `chat_read` and `workspace_diff`
read their own workspace when nothing is named, and may name any other that is not archived,
because reading acts on nothing. What they bring back is fenced as untrusted content. See
"Reading another workspace" below.

The token is **not a secret and must not be commented as one**. Any process running as the user can
read `ps`, the mode 0600 config file and the socket itself, and an agent has the user's whole home
directory anyway. What actually holds, whoever connects, is server side: parentage read from the
database, git's own safety reports, and counts. Session tokens are minted per launch and held in
memory only, so a quit retires them; the owner's standalone token is the one exception and
`BridgeOwnerToken` sets out at length why a coupling that breaks every time the app restarts is not
a coupling.

The socket path is derived from the database path through the same fingerprint the tmux socket name
uses, so Unified Dev and Unified Dev (Dev) can never land on one. The landmine there is `sockaddr_un.sun_path`,
104 bytes on macOS, which **truncates in silence**: two instances whose paths agree for the first
103 bytes quietly share one socket, which is the exact failure the fingerprint exists to prevent.
`BridgeSocketPath` asserts the length rather than trusting that it fits.

### The owner's token inside a worktree

**The owner's standalone token is refused at the handshake when the shim is running inside a live
workspace.** The owner registers Unified Dev in `~/.claude.json` at user scope, and Claude Code
applies user scope to every session on the machine, the ones Unified Dev launches included. So
every workspace agent ran two shims, its own on its session token and the owner's on the standalone
one, and held the owner's tools through the second. The different server names kept the two
registrations from shadowing each other and did nothing about an agent holding both.

The test is the shim's working directory, read from the peer process on the socket
(`UnixSocketConnection.peerProcessID`, then `ProcessWorkingDirectory.of`). A CLI starts its stdio
MCP servers where it is running, and Unified Dev runs a workspace agent in its worktree, so an owner
shim started by a workspace agent is sitting in a worktree. Ask Unified Dev's shim runs in
`Application Support/Unified Dev/Ask` unless the owner points an Ask tab somewhere else, and a
terminal the owner opened anywhere else is anywhere else. An environment marker was the obvious
signal and the wrong one: Codex hands an MCP server a short allow list of variables rather than its
own environment, so nothing Unified Dev set on the agent would reach the shim. The owner running
their own `claude` inside a worktree, or an Ask tab pointed into one, is refused too, with a
sentence saying to run it from outside Unified Dev's workspaces, because that client is standing in
a workspace just as surely. A directory that cannot be read lets the connection through, because
failing to see where a caller is is not evidence that it is somewhere it should not be.

Like the token, this is not a security boundary: an agent that wants the owner's tools badly enough
can start the shim from another directory. What it stops is the ordinary case, an agent holding the
owner's tools because a config file was read. See `BridgeOwnerPlacement`.

### The profile a caller is limited to

**A caller lists, reads, starts and talks only to projects, workspaces and chats of its own profile,**
unless it may reach another and names it, which is [Reaching another profile](#reaching-another-profile).
`BridgeProfileScope` is the one place that decides a caller's own, and every tool takes its rows from there.

| Caller | Its profile |
| --- | --- |
| `workspace`, an orchestrator included | The profile of the project its workspace belongs to |
| `owner`, an Ask chat during a turn | The profile active when that turn started |
| `owner`, the standalone token, or an Ask chat between turns | `Store.activeProfileID()`, read on each call |

A `workspace` identity whose workspace or project row has gone has no profile, and its scope is empty.

An Ask chat's pin is held in `BridgeRegistry`, in memory, by the chat's session. `TranscriptModel` sets it
when the chat starts running, whether the owner sent a message or the agent started the turn itself, and
releases it when the turn ends. A chat already running keeps the pin it has, so a switch of profile mid
turn does not move what the chat is doing, and the next turn takes the profile active then. A pinned profile deleted during
the turn leaves the scope empty rather than falling back to the active one.
`reveal` is refused while the pin is not the active profile: the answer names the profile the workspace
is in, and the window does not move.

`workspace_start` and `project_add` answer with a `profile` field holding the name of the profile the
workspace or project landed in, for every caller, so a caller can say where its work went.

A workspace or a project in another profile is answered exactly as one that does not exist would be,
archived rows included: the same refusal, with no name from that profile in it or in any list of known
names. A path in `work_suggest` is treated the same way: a repository registered under another profile
gets the `.folder` card an unregistered path gets, and the refusal comes at launch.

The one exception is `project_add`, which only the owner has. Given the path of a repository registered
under another profile, it refuses with a sentence saying it belongs to another profile, without naming
that profile or returning its row, because the alternative is a second registration of one repository.

A card stays inside the profile of the workspace that filed it. A `.remote` card is adopted only by a
project in that profile, and `WorkSuggestionLaunch` refuses to start a card whose project is in any other,
including one moved after the card was filed and a `.folder` that `WorkSuggestionLaunch.admit` resolves
elsewhere. `WorkSuggestionProfile` holds that decision. A card from an Ask chat has no workspace and so
no such limit.

The scope is for answering a caller, not for running the app. `BridgeServer` reads every workspace
when it places the owner's token, since a shim inside a workspace of any profile is refused. The
ceiling on what the owner's client starts in a window counts across all profiles, because it limits
this Mac rather than a profile.

### Reaching another profile

A profile can be opened to the others, and callers can then cross into it. The default is closed:
with every switch off, every tool answers as it does without this section. The rule is about the
destination: whatever comes from outside a profile goes through the orchestrator of the project it is
for. A profile's switch decides only what comes in. A chat in a closed profile still reaches every
profile that is open, under the same conditions as a chat in an open one, and its message names the profile,
workspace, project and chat it came from, as any message from outside does. Nothing comes back into a
closed profile: a reply is refused like any call into it, and `notify_when_done` is not set up for a message
it sends, which the answer says (`WorkspaceMessageComposer.noticeComesHome`). A watch made while the profile
was open is still kept, as below.

**Who.** `BridgeProfileReach.caller` reads it from the rows on every call, and from what the chat's bridge token recorded when it launched.
`BridgeProfileReach.mayCross` then decides it for one of two purposes: talking, which is `project_list`,
`workspace_list` and `workspace_say`, and reading, which is `chat_list`, `chat_read` and `workspace_diff`.

| Caller | May talk when | May read when |
| --- | --- | --- |
| A top level chat of a project's orchestrator workspace, on Claude Code or Grok | The destination is open, and the owner approves the call | The same |
| The owner's own clients: an Ask chat and the standalone token | The destination is open | The destination is open |
| Any other workspace chat on Claude Code, a subagent included, launched in Accept edits | The destination is open, and the owner approves the call, and only to an orchestrator | Never |
| Any other workspace chat on Claude Code launched in Auto, Plan or Bypass permissions | Never, and it is told why | Never |
| Any other workspace chat on Grok, Cursor or OpenCode | Never | Never |
| A chat running on Codex | Never | Never |

A workspace that stops being the orchestrator becomes an ordinary workspace at its next call: it can still
talk to another profile's orchestrators and can no longer read there. `isOrchestrator` is written only by
the app.

**An ordinary workspace talks to the orchestrator.** Its `workspace_list` lists the orchestrators alone, in
its own profile and in another, by id, name and project and nothing else, since those are the workspaces it
may write to across profiles. `BridgeProfileReach.lists` decides which rows, and `WorkspaceListBriefRow` what
they hold. In another profile, `workspace_say` from an ordinary workspace looks the name up among that
profile's orchestrators alone, through `WorkspaceSayDestination.orchestrators`, so any other workspace there
is refused in the same words as one that does not exist, and the refusal points at `workspace_list` and at
passing the project. A read in another profile is refused with a sentence that points at the orchestrator,
which can read and answer. A message may name the project instead of the workspace, and goes to that
project's orchestrator; naming both is refused.

**A project with no orchestrator.** A message for one does not start anything. It becomes a card for the
owner below the sender's message, in the shape of `work_suggest`, carrying the message, and the answer says
so. Only the owner's click on Start Orchestrator acts on it: `OrchestratorRequestLaunch` starts a workspace
in that project as its orchestrator and delivers the message to it, in the same envelope as any message from
outside. If the project has gained an orchestrator by then, the message goes to that one and nothing new is
started. The click is judged again: a card whose destination has since been closed, whose chat has moved
to Codex, or whose workspace was archived, is refused and stays waiting. The refusal, which only the owner
sees, says which: `BridgeProfileTrouble.closedToOutside` for a closed destination, and
`WorkSuggestionWording.senderCannotCross` for a sender that can no longer cross. The sender's own profile
being closed does not stop it. A card whose sender has since become that
project's orchestrator is not delivered to itself. A card from the owner's Ask chat always arrives in the
envelope from outside, with its profile given as unknown, since which profile that chat was in is not kept. A delivery
that fails leaves the card waiting with the orchestrator already in place, and the next click delivers to it.
`notify_when_done` does not apply to a message waiting on a card. The sender can withdraw it with
`work_withdraw`. No bridge tool starts an orchestrator.

**A closed destination is answered as one that does not exist.** Every tool, `workspace_say` included,
answers a closed profile and an invented one with `BridgeProfileTrouble.unreachable`, which says that no
open profile it can reach has that name, that the owner opens one in that profile's own settings, and that
`profile_list` names the ones open to it. It does not say whether a closed one exists. Only the owner's
card, which no agent reads, names a closed destination.

**A caller held on its own side is told which side.** Before any other profile is looked up,
`BridgeProfileReachRefusal.ownSide` asks whether the caller could leave its own at all, from the caller alone:
it was not launched asking (`launchedUnasked`), or it runs on an agent that never crosses (`agentConfined`).
The answer is the same for `all`, for a profile that exists and for one that does not, so it says nothing
about any other profile. Naming the caller's own profile is answered before this, as its own.

**The owner approves a workspace's crossing.** Every call from a workspace chat that names a `profile`
stops on the permission card, reads included, because what it reads could steer it and what it sends wakes
an agent. `BridgeToolApproval.isSelfApproved(toolName:input:inWorkspace:)` decides it, and the same call
decides how a stored card reads afterwards. This rule adds no card for an Ask chat or the owner's standalone client,
which are the owner's own. Codex has no approval request for an MCP tool call, so nothing could stop it, and
`BridgeProfileReach.caller` confines it instead. An orchestrator always launches in a mode that asks, and
that launch is what the bridge token records: a chat at rest when its workspace becomes the orchestrator
cannot cross until its next start, which is its next message.

**An ordinary workspace crosses only from a chat launched asking.** Claude Code puts every call to the
owner in Accept edits; in Auto a classifier may let it through, Bypass permissions, which is the default,
never asks, and Plan does ask but approving the plan moves the same process to Auto or Bypass
permissions. Accept edits is kept until the app starts the CLI again, whatever the chat's row says
meanwhile, since a change of mode in the app starts it again, so the bridge token records it: `BridgeServer.attach` sets `launchedAsking` from
`BridgeProfileReach.asksTheOwner`, and an orchestrator's launch, which always asks, sets it too.
`BridgeProfileReach.caller` makes an ordinary chat launched any other way `.unasked`, which reaches no other
profile. Naming any other profile, or `all`, answers with `BridgeProfileTrouble.launchedUnasked`, which says
why and what the owner can change, in the same words for a profile that exists and one that does not. A chat switched to Accept edits
crosses from its next start, which is its next message. Grok, Cursor and OpenCode stay confined:
an approval Grok remembers covers a whole tool, so a call allowed in a chat's own profile would carry every
later call that names another.

A call that names a `profile` can never be allowed always: `PermissionAsk.canWiden` is false for it, so the
card offers no "always allow", `PermissionAnswer.encode` sends the CLI nothing to remember, and
`SessionGrants` stores no grant from it. This holds for an orchestrator too. An ordinary chat launched
asking also gets `ask` rules for the tools that can name a profile, `BridgeToolApproval.claudeCrossingPermissions`
in its `--settings`, because Claude Code puts an `ask` rule above an `allow`: a rule allowing the bridge in
the owner's own settings cannot skip the card. A call that names no profile is still approved by
Unified Dev itself, so the rule adds no card the owner sees.

**The role does not land on a workspace at work.** The limits on an orchestrator are applied when an agent
launches, and a turn already running under `acceptEdits` or `bypassPermissions`, Codex's sandbox once its thread is
open, and a terminal chat have nowhere to be stopped afterwards. So `Store.setOrchestrator` refuses, in the same
write, when any chat of the workspace is running or waiting, crew included, and when the app says something is still at work there:
a background task of a chat, or an agent process it finds in one of the workspace's terminals when asked, or it cannot tell.
Make Orchestrator then leaves that workspace exactly as it is and starts a new one as the orchestrator, opened
with `OrchestratorHandover`'s account: the workspace it stands in for, its chats, the most recent of their conversations, any agent
found in a terminal, and the instruction to leave those agents running. Every name and transcript in that account is fenced as untrusted text. A workspace whose chats are all at rest takes the
role where it stands.

**What.** Reading and talking, and nothing that creates: `project_list`, `workspace_list`, `chat_list`,
`chat_read`, `workspace_diff` and `workspace_say`. `workspace_start` stays inside the caller's profile, and
`agent_say` and `agent_start` act inside one worktree, so they have nothing to cross.

`workspace_list` has otherwise been the owner's alone. It is served to a workspace chat only while that
chat may leave its profile to talk, and answers exactly as an unknown tool otherwise, in `tools/list` and in
`tools/call`, through `BridgeToolHandling.isServed`. An orchestrator's list is always fenced.

**The switch.** One per profile, in Profile Settings, titled Reachable from other profiles, under the key
`ProfileBridgeSwitch.key(profile:)`, off by default and read on every call. It decides whether other
profiles can reach this one, and nothing about where this one's chats can reach. It is held to the rule of who may write the orchestrator's unasked switch: it lives
in the app's `settings` table, only its settings section writes it (and a seeded preview), and
`OrchestratorUnaskedReachTests` reads it back after calling every bridge tool in every role.

**Naming a target.** The tools above take an optional `profile`, an id or a name no other reachable profile
shares, and the two lists also take `all`, meaning the caller's own and every one it can reach. Without it
nothing changes: an id from another profile is still answered as if it did not exist, so crossing is always
something the caller said out loud. Naming the caller's own profile is not a crossing. Once the caller itself
may leave, a profile it cannot reach gets one refusal, whether it is closed or does not exist.

**Finding a profile.** `profile_list` answers the caller's own profile, whether it is open to others, and
every other open profile the caller can reach for talking, by id and name; when it reaches none because of
its own condition, the note is the sentence above for that condition. It names other profiles, so every
call from a workspace chat stops on the permission card exactly as a call that names a `profile` does:
`BridgeToolApproval.crossesProfile` is true for it whatever its input, so `isSelfApproved` refuses it in a
workspace, the card offers no "always allow", and it is among the `crossingTools` an ordinary chat gets an
`ask` rule for. Unified Dev never approves it by itself, so the owner's own Ask chat shows the card whenever its mode asks, and the standalone client, which has no card, is not stopped; both are the owner's own. A workspace's answer is fenced. A chat
that cannot cross, Codex among them, gets only its own profile back, so a call nothing could stop reveals
nothing. `all` is reserved on the two lists, so
a profile called All is named by its id there, and `include_github` is refused with `all` because it starts
processes per workspace. No switch changes what `tools/list` offers: `workspace_list` is served by who the
caller is, not by which profiles are open.

**What comes back from a read.** Every answer that crosses is fenced as untrusted content, and names the
profile it belongs to. Refusals inside a crossing list workspace ids, never names, and a refusal from the
app, a project lookup or git there is one generic sentence. A notice about the other side names it by id. What was read can still be repeated by the reader, so
text planted in one profile can travel to another if the owner approves carrying it.

**What the receiver sees.** A message from another profile gets an envelope of its own, written by
`WorkspaceMessage`: the profile and workspace id it came from, then between the untrusted markers the names of
its workspace, project and chat, and the text, and a sentence saying that it does not carry the owner's authority and to ask the owner before
acting on it. That holds for the owner's own clients as well, since an Ask chat reads untrusted text too.
A message still waiting in a queue was written when it was sent and arrives as written, even if a switch is
turned off meanwhile.
Inside one profile the envelope and its authority are as described under "Talking to another workspace".

**Accounts.** A turn that a message wakes in another profile runs on the account of the destination's
project, as every chat in that workspace does, and never on the caller's. With no account available there,
the turn does not start and the chat says why.

**What comes back.** `notify_when_done` crosses back to the asking chat, with the report fenced as usual and
naming the other profile, and a watch made before a switch is turned off is still kept. An Ask chat has no chat
to be told in, so it is not offered one. Answering with `workspace_say` follows the rule
above: an orchestrator can answer any sender, and an ordinary workspace on the receiving side can answer
only a sender that is an orchestrator, and the envelope says so. The announcement to a project's orchestrator is per project, so it never crosses a profile.

**What this does not hold.** The scope is the bridge's. An agent runs as this user, and anything it can run
outside the bridge is limited by what that user can read, as section 2 says of the token.

## 3. The tools

Fifty-four, each a type of its own in `Sources/Core/Bridge/`, each carrying its own role
gate. A list of handlers rather than a switch, because a switch would put every tool in three
places: the listing, the dispatch and the gate.

| Tool | What it does | workspace | owner |
| --- | --- | :---: | :---: |
| `whoami` | What this connection is: the workspace and its branch, the worktree path, the project, whether the workspace was created by the owner or by another agent, and whether it is the project's orchestrator. From the owner's own client, which copy of Unified Dev was reached and how much it is holding | ✓ | ✓ |
| `profile_list` | The caller's own profile, whether it is open to others, and every other open profile it can reach, by id and name, or which condition of its own stops it reaching any. Stops on the permission card from any workspace chat | ✓ | ✓ |
| `project_list` | Every project of the caller's profile: name, path, default branch, how many workspaces it has, how many of those have an agent mid turn and how many have one stopped on a question, whether it is still where Unified Dev recorded it, whether it is hidden. A workspace agent calls it to find a project to hand work to | ✓ | ✓ |
| `project_add` | Register a git repository that **already exists** as a project | | ✓ |
| `project_hide` | Take a project out of the sidebar. A view preference and nothing more | | ✓ |
| `project_unhide` | Put it back, in the place it already had | | ✓ |
| `workspace_list` | Every workspace of the caller's profile, its state, its worktree path, its chats and their cost, what an agent is stopped on, what is queued and why, and which one is the project's orchestrator. Served to a project's orchestrator too, only while it may leave its profile | ✓ | ✓ |
| `workspace_start` | Cut a worktree and put an agent in it with a task, on a new branch, existing branch or GitHub pull request, in the caller's own project or another it names. With notify_when_done, or always when the caller is the project's orchestrator, the calling chat is told once when the new agent's first turn comes to rest | ✓ | ✓ |
| `workspace_rename` | Give a workspace the name the work in it turned out to be about. Its own, or one it started (by name or id), for a workspace agent; any of them, named out loud, for the owner | ✓ | ✓ |
| `workspace_archive` | Archive a workspace through normal safety checks, keeping its branch and history. For a workspace agent, its own once the turn asking for it has ended, or one it started, by id and at once; any of them, named out loud and at once, for the owner. The project's orchestrator is refused until it stops being one | ✓ | ✓ |
| `workspace_merge` | Ask a workspace's own agent to merge its pull request | | ✓ |
| `workspace_say` | Put a message in another workspace's chat, with the owner's authority unless it crosses a profile, headed with the workspace, project and chat it came from. Cancellable from either end until the agent there starts reading it. Refused past thirty messages to one workspace in ten minutes, or for the same words twice in that window, except from the owner's own client. With notify_when_done, Unified Dev tells the calling chat once when the turn it caused finishes, fails or blocks on the owner | ✓ | ✓ |
| `reveal` | Point Unified Dev's window at one workspace, or at Home narrowed by project, scope and search. Navigation and nothing else: it creates nothing and archives nothing | | ✓ |
| `pane_open` | Open a chat, a terminal or a browser in a new tab of the caller's own workspace. A browser opens behind the tab in front and fetches nothing until somebody looks at it | ✓ | |
| `pane_split` | Add a pane inside the calling chat's tab, defaulting to a new chat on its right. A browser pane opens blank | ✓ | |
| `pane_close` | Take one back off the screen, or close the workspace's canvas with kind `canvas` | ✓ | |
| `pane_rename` | Give a tab a name the reader can find it by | ✓ | |
| `pane_list` | What the workspace has open: each pane's kind, its name, whether it is in the tab in front, for a browser its number and its address, and for the canvas the `path` of the file it shows | ✓ | |
| `workspace_tabs` | The same window read as a strip: every tab in order, what it is called, which one is in front, and one true thing about what is in it | ✓ | |
| `chat_list` | Unarchived chats in the caller's workspace, or in another it names by id or unique name, including subagents, with IDs, titles, states and message counts | ✓ | ✓ |
| `chat_read` | Read one of those chats by ID or exact title, with bounded pages of stored transcript content, fenced as untrusted when it is another workspace's | ✓ | ✓ |
| `workspace_diff` | What a workspace has changed, its own or another it names: branch, base, changed files with counts, and the unified diff the review pane shows, in pages whose cursor refuses a diff that moved | ✓ | ✓ |
| `workspace_tab_select` | Make one of those tabs the one in front, by its number or by its name. It cannot make one, and it refuses a tab with a browser in it | ✓ | |
| `browser_read` | One browser's toolbar: address, page title, load state, whether Back and Forward would do anything | ✓ | |
| `browser_reload` | Fetch that page again | ✓ | |
| `browser_go` | Point a pane that is already open at another http or https address | ✓ | |
| `browser_scroll` | Move the page up, down, to the top or to the bottom, and say where it ended up | ✓ | |
| `browser_screenshot` | A picture of the pane as it is on screen, as an image | ✓ | |
| `browser_text` | The visible text of the page, wrapped as untrusted content | ✓ | |
| `browser_snapshot` | The page as a numbered list of the things a reader could use, each with a reference like `[e7]`, wrapped as untrusted content. A password says its length and never its value | ✓ | |
| `browser_click` | Press the element one of those references names | ✓ | |
| `browser_fill` | Type into the field one of them names, including a password field, and report only how many characters went in | ✓ | |
| `browser_press` | Send one of eight named keys to the page, or to one element | ✓ | |
| `browser_wait` | Wait, up to a ceiling, for a phrase to appear, for one to leave, or for the load to finish, and say which of the two happened | ✓ | |
| `terminal_start` | Open a terminal tab and run a command visibly inside it. Refused in the project's orchestrator, with `terminal_write` and `terminal_send_key`, because a shell there could edit what the orchestrator may not | ✓ | |
| `terminal_read` | Read recent rendered output from a terminal tab | ✓ | |
| `terminal_write` | Type text into a live terminal, optionally followed by Enter | ✓ | |
| `terminal_send_key` | Send Enter, Control-C, Tab, Escape or an arrow key to a live terminal | ✓ | |
| `media_show` | Show an image or video from the workspace inline in its chat | ✓ | |
| `canvas_show` | Show one file from the caller's own worktree in the workspace's canvas tab, which reloads when the file changes: HTML, Markdown, SVG or a PNG, JPEG, GIF or WebP image as a page, or a `.udcanvas` document in the canvas editor, where the owner draws frames, text, notes, shapes and pen strokes, comments, plays the frames as slides and exports them as PNG. A `.udcanvas` path that does not exist is created as a blank document with one frame and any folders it needs, except in a project's orchestrator, which is refused | ✓ | |
| `canvas_read` | Read a canvas document in the caller's own worktree: its frames and elements with their revisions, the comments in the file still open, and the size each text really takes once laid out. All of it is marked as data read from the file, between the markers every bridge answer quoting untrusted text carries. One answer holds about 32,000 characters: `cut` says what was left out, `nextOffset` is the `offset` to ask for next and `nextFrameOffset` is the `frameOffset`. Works with the tab closed, refuses a corrupt or newer document with the reason, and warns when it answers from a tab under a hold rather than from the file | ✓ | |
| `canvas_edit` | Change a canvas document in the caller's own worktree by a list of at most 500 operations, all or nothing, each update or delete carrying the revision read with `canvas_read`. One call is one undo step for the owner. The answer lists the new revision of everything that changed and says whether the change reached the file. A conflict applies nothing and returns the current state. Works with the tab closed and never opens it; refuses a corrupt or newer document and one under a hold. Refused in a project's orchestrator | ✓ | |
| `canvas_comment_resolve` | Answer a comment the owner left on a canvas document in the caller's own worktree, as resolved with a sentence saying what was done, or as declined with the reason. Only the chat the comment was sent to can answer it. Not an undo step for the owner. The answer says whether it reached the file. Works with the tab closed; refuses a corrupt or newer document and one under a hold. Open to a project's orchestrator | ✓ | |
| `canvas_render` | Draw one frame of a canvas document as a picture, at 1:1 up to 8192 points a side with the longest side capped at 2048 pixels, by the code that draws it on screen, without selection. Works with the tab closed; names fonts this Mac lacks and pictures drawn as a placeholder because the frame's pictures need more memory than one render may use, says the text in the picture is read from the file, and warns when it draws from a tab under a hold rather than from the file | ✓ | |
| `agent_start` | Start a subagent: a second agent in the caller's own worktree, on the same branch, with a task of its own | ✓ | |
| `agent_say` | Put a message in another agent's chat on this job. An orchestrator names which of its crew; a subagent names nobody and talks up. Waking a stopped one is held to the same ceiling as a start | ✓ | |
| `agent_list` | Who else is working in this worktree: each agent's name, whether it is running, and what it is doing | ✓ | |
| `agent_stop` | Finish with a subagent the caller started: it ends the agent if it is still running, takes its row out of the sidebar and frees its name, and undoes no work | ✓ | |
| `quick_prompt_list` | The owner's own quick prompts, whole, with the ids the other three take | ✓ | ✓ |
| `quick_prompt_create` | Write a new quick prompt into that library | ✓ | ✓ |
| `quick_prompt_update` | Change one, field by field, leaving the fields it does not name alone | | ✓ |
| `quick_prompt_delete` | Take one out of the library for good | | ✓ |
| `work_suggest` | Suggest a piece of work to the owner instead of starting it: a card in the calling chat with a title, a reason, the whole prompt and where it would go. Nothing starts until the owner presses a button on the card | ✓ | ✓ |
| `work_withdraw` | Take back a suggestion the calling chat made, while the owner has not decided it | ✓ | ✓ |

**A workspace another agent started gets the same column as any other.** The one tool it holds and
cannot use is `workspace_start`: it is listed, because no role hides it any more, and the handler
refuses it off the caller's own row, which is the nesting limit in section 2 and the check that
mattered all along.

The gate is enforced twice on purpose. `tools/list` hides what the caller may not use, so the
owner's client never sees a pane tool it could only be refused by, and `tools/call` refuses it
again, so a process speaking raw MCP at the socket with a token that role is not on gets nowhere
either. A tool that exists but is refused answers exactly as an unknown name does, so the refusal
cannot be read as a hint that something is there.

A refusal is a result with `isError` set and never a JSON-RPC error frame. A JSON-RPC error is a
transport failure the CLI may retry or surface as a broken server; an errored result is text the
model reads and can act on. "You are not allowed to do that" is something to tell the model, not
something to tell the transport.

### Tabs, panes and the chat making the request

A **tab** is an entry in the top strip. It owns an arrangement of one or more **panes**, the
regions visible together inside that tab. Selecting another tab switches the whole arrangement.
`pane_open` creates a separate tab; `pane_split` adds a region to an existing tab. Both tools,
`pane_list` and `workspace_tabs` explain this distinction in their model-facing descriptions.

For "add a pane", "split pane in this chat", or "split vertically next to this chat", the model
should call `pane_split` with no arguments. It defaults to a **new chat on the right**, separated
by a vertical divider. This is `direction: "beside"` on the wire and `SplitAxis.horizontal`
internally. `direction: "below"` stacks the panes with a horizontal divider. The optional `kind`
can instead request a terminal or browser; `title` names the new content, not the containing tab.
A browser pane opens blank and a `url` for one is refused, for the reason given under the browser
pane below.

The default `target: "this_chat"` comes from the authenticated session, not the tab or pane that
happens to have focus when the agent calls. The resolver finds that conversation inside its tab,
including when another chat roots the tab or a terminal has focus beside it. A missing chat is
refused before anything is created. `target: "active_pane"` follows the selected tab's focused
pane only when explicitly requested. Chat creation is awaited and the destination revalidated
before placement, so a changed target cannot produce a false success or split unrelated content.

### Reading another workspace

`chat_list` discovers the unarchived sessions in a workspace, including crew members. `chat_read`
accepts an ID from that list or an exact title. Shared titles are refused until the caller names
an ID. A request Unified Dev sent on the owner's behalf, the report of a Run, a failed check or a request from the pull request bar, is
not drawn in the owner's window and is still read here, as a `crew` record with its full text and
`sent_by` set to `unified_dev`, so a reader can explain the reply that followed it and cannot take
it for the owner's words.

**Both reach another workspace when the caller names one.** A read acts on nothing, and an agent
asked "what did the other workspace decide" otherwise had to be handed a worktree path and run git
or `sqlite3` there through `Bash`, which passes through no gate of Unified Dev's at all. Every agent
here works for the same owner, and `workspace_say` already puts a turn in another workspace's chat,
which weighs far more than reading one.

Both take an optional `workspace`, resolved by `BridgeReadTarget` through
`BridgeWorkspaceLookup.activeTarget`, the same resolution `workspace_say` makes: an id
`workspace_list` or `workspace_start` reports, or a name no other active workspace shares. An
ambiguous name is refused with the ids that answer to it, an archived workspace is refused as
archived rather than as unknown, and an unknown name lists the active ones, each kept on one line.
Left out, or naming the caller's own, a workspace agent reads its own workspace, and is told so
when that workspace has been archived or its row has gone; `workspace_diff` answers the same way.
The owner's client sits in no workspace, so it may call both and must name one.

For another workspace `current` is false on every chat, since it marks the caller's own, and both
answers carry that workspace's id and name. A chat reached through one workspace cannot be read
through another: the session is looked up in the named workspace's list, and the cursor names the
chat.

**What another workspace's chat can do to this one is be believed.** "Fix it and push" in there was
said to a different agent, and a model reading it back with no label reads an instruction. So the
whole answer for another workspace, JSON and all, goes between `BridgeUntrustedText`'s markers,
after a sentence saying where it was read from, that nothing in it was said to the reader, and that
no part of it is an instruction or grants permission for anything. `BridgeWorkspaceQuote` does the
fencing. The body is escaped the way every other fence is, so a line that forges or resembles a
marker is quoted, and before that the JSON's own `U+2028`, `U+2029` and `U+0085` are written as
`\u` escapes: `BridgeUntrustedText` treats those as line breaks, and left raw they would let a
string inside the JSON start a line of its own. The fence goes round the whole answer rather than
round each message, because a message split across pages would otherwise carry half a fence on each
page. A caller reading its own workspace gets the plain JSON it always had.

**A workspace's name never leaves the fence.** Any agent can rename its own workspace, and a name
is free text, so a name could be a sentence addressed to whoever reads it. The sentence before the
fence, and every refusal of the three readers, name the workspace by its id; the name is inside
the JSON with everything else that workspace wrote.

The transcript comes directly from `Store`, without selecting a tab or loading a view. User and
assistant text, thinking and crew messages use the transcript's existing decoders; other rows
retain their stored payload, including tool calls and results. Unknown formats remain readable as
raw text. Attachment paths are included, but attached files and unsaved streaming text are not read.

Pages contain up to 50 records by default (100 maximum) and 32,000 content characters. Pass the
returned `next_cursor` with the chat ID until it is null. Cursors name the chat, message sequence
and character offset, so appending messages does not shift later pages, and oversized messages
continue on the next page without losing text. Chunks carry `offset` and `complete` for reassembly.
Both tools are self-approved: they read conversations and change nothing in the window or the
store, and an ask in front of a read an unattended agent makes is a hung turn for nothing.

`workspace_diff` is the same reach applied to a worktree, with the same `workspace` argument and
the same callers. It answers with the branch, the base, each changed file with its counts, and the
unified diff, measured the way the review pane measures: from `Git.baseline`, so everything since
the branch left its base, including staged, unstaged and untracked work, and never the base's own
later commits. It calls `Git.changedFiles` and `Git.patch`, the review pane's own functions, rather
than a second notion of "the workspace's changes"; the whole branch is one `git diff` plus one call
per untracked file. `path` narrows it to one file. Pages hold 32,000 characters and end on a line
break; the cursor carries an FNV-1a fingerprint of the diff and the path, so a file saved between
two pages refuses the cursor rather than stitching two diffs together. The file list, capped at
500 entries with `files_not_listed` counting the rest, comes with the first page only. A workspace
whose worktree is not on disk is refused in a sentence.

**Every page rebuilds the diff, so the diff is held to a budget.** `WorkspaceDiffBudget` leaves the
whole-branch diff out, and says so in `diff_omitted`, when the changes pass 20,000 lines added and
removed or 200 untracked files: each untracked file costs a `git diff --no-index` of its own, and
an unignored build directory would otherwise start thousands of processes inside the owner's app
for every page. The file list still comes back, and one `path` reads one file, which is refused
past the same line budget. A path matches a file's own path before the old path of a rename, a
renamed file's patch names both paths so git shows the rename rather than a new file, and an
untracked repository nested in the worktree is left out of the whole-branch diff rather than
failing it. Its answer is always fenced, its own workspace's included, because a diff is file
content and anything could have written it. It is self-approved on the same argument as
`chat_read`.

### A workspace existing and an agent running in it are two numbers

`project_list` used to report one number per project, counting workspaces whose state was not
`archived`, under the key `workspaces_running`, described as "how many workspaces it has running"
and listed here as a "live workspace count". Three names for a count of workspaces that merely
exist. An agent read it, told the owner that four projects had a workspace running, then called
`workspace_list`, found `agent_running: false` on every row, and reported the two tools as
contradicting each other. They never had. Both read the same table through the same
`state = 'active'` predicate; only the name was wrong, and the name is what a model acts on.

So `project_list` now reports `workspaces`, `agents_running` and `awaiting_permission` per
project, and both tools answer from one `BridgeWorkspaceCensus`: one read of the workspaces and
one of `Store.sessionActivity`, with the two turn questions put to `AgentTurns`, which is the same
rule the sidebar mark asks. A project's `workspaces` is therefore exactly how many rows
`workspace_list` prints for it, and its `agents_running` exactly how many of those are marked
`agent_running`. Two tools deriving that separately is two rules to drift.

One number kept its old sense deliberately: `WorkspaceStartAllowance.running`, the ceiling of
eight, or sixteen for a project's orchestrator, on the workspaces an agent started, counts workspaces that are not archived rather than
agents mid turn. That is a brake on worktrees held open, not on turns in flight.

### What `setup_state` says

`workspace_list` reports each workspace's `setup_state` as one of `pending`, `running`,
`succeeded`, `failed`, `ignored` or `skipped`. `ignored` is a failed run the owner has read and
dismissed with Ignore on the setup row. The log is kept, the row's `status` stops being
`setupFailed`, and a terminal in the worktree stops warning that dependencies may be missing. It is
not a success: a caller deciding whether a worktree's dependencies are installed should treat
`ignored` as it treats `failed`. Running setup again moves it to `running` like any other state.

### The thirty-one that need the app, and the seventeen that do not

`BridgeToolbox.standard` holds the seventeen that reach nothing but the store, and it is what a
`BridgeServer` built without the app serves, which is every test that did not ask for more.
`AppModel.bridgeToolbox()` adds the other thirty-one to it, because starting a workspace has to reach
the main-actor graph that runs one, asking for a merge has to reach the same path the Merge button
takes, moving the selection is the window's own, and a pane is a thing the window owns. Each of
those crosses the line as an injected closure
(`WorkspaceStarting`, `WorkspaceMergeRequesting`, `Revealing`, `PaneOpening`, `PaneSplitting`,
`PaneClosing`, `PaneRenaming`, `PaneListing`, `BrowserPaneCommanding`, `TerminalStarting`,
`TerminalPaneCommanding`, `WorkspaceTabListing`, `WorkspaceTabSelecting`, `CrewStarting`, `CrewSaying`, `CrewStopping`, `WorkspaceMessageDelivering`), so a pane an agent asks for is the pane the
menu makes, unchanged and not copied. It adds them **to** `.standard` rather than listing its
handlers again, because a copy of that list is a copy that drifts: a tool added to the core toolbox
and not to the app's would pass every test in the suite and never reach the running app.

**The two tab tools are on that side for a reason worth stating plainly, because it is not the
same reason the browser tools are there.** A browser is a `WKWebView`, which is obviously the
window's. A tab looks like data and is not: the tool tabs are a JSON blob in user defaults that
only `CenterTabStore` reads, the split arrangements are more of the same under `WorkspaceTabsStore`,
and **which tab a workspace is in is in memory on the main actor and is written nowhere at all**.
There is no table to read, so there was never a version of these two that lived in
`BridgeToolbox.standard`. What that forces is the pair of closures above, and the same rule the
rest of the family follows: no workspace argument, so the caller reads and moves the strip of the
workspace it is standing in and no other.

**The browser and terminal seams are how their tools see the window.** `PaneListing` takes a
workspace and gives back a `PaneCensus`, and that shape is the point: there is no argument on it
that could ask the window to do anything, so the tool that reports cannot act. `BrowserPaneCommanding`
carries one `BrowserPaneCommand` and is what the other six share, so the pane a call means is
resolved once, by `BrowserPaneChoice.choose` in the core, rather than six times in the window.
`TerminalPaneCommanding` does the equivalent for terminal reads, text and control keys.
`TerminalStarting` is separate because opening a blank pane is self-approved while running a
command is not. Folding the command into `pane_open` would let it bypass the agent's permission
mode.

**The four quick prompt tools are the case that shows where the line really is.** They write, and
they need no seam at all, because a quick prompt is a row in `quick_prompt` and `Store` is an actor
a handler on a background task calls directly. The window finds out the way it finds out about
every other write: the update hook publishes the `quickPrompts` domain and `QuickPromptCatalog`
re-reads. The panel used to read that list once and never again, so a prompt written over the
bridge was invisible for the rest of the session; it subscribes now. An injected main-actor closure
here would have been a second way to write the same row.

`workspace_rename` is on the same side for the same reason, and it is worth saying because a
workspace looks far more like a thing the window owns than a quick prompt does. It is not. A
workspace's name is one column of the `workspaces` table, the sidebar draws it from there, and the
sidebar re-reads on the `workspaces` domain already, because that is how it finds out about a
rename typed into the row itself. The write goes through `Store.update(workspaceID:)` and never
`upsert`: a diff stat refresh writes to that row every few seconds and an agent turn writes to it
for ten minutes, and a whole-value write would put both back to whatever the rename had read. See
`Tests/CoreTests/WorkspaceWriteIsolationTests.swift`, which is that bug written down.
`workspace_diff` is on that side too: it reads a worktree through git, which needs no window
either.

**The four crew tools split three to one, and the line runs where it always does.** `agent_list`
reads a crew, which is rows in `sessions` joined by `parent_session_id`, so it is in
`BridgeToolbox.standard` beside the quick prompt tools and reaches no window at all. `agent_start`,
`agent_say` and `agent_stop` are on the other side, because one runner per session is held in
main-actor UI object identity: starting a chat, sending a turn into one and stopping one all happen
in the graph that owns those runners, and a handler that reached round it would put a second CLI
process on the same worktree. `CrewSeam` is the three closures, and `Crew` is every rule they are
held to, both in the core and both testable without a socket, a worktree or a running CLI.

`BridgeServer` **never constructs an `AgentRunner`, and nothing added to it ever may.** One runner
per session is held in main-actor UI object identity, and a handler that built its own would put a
second CLI process on the same session row and the same worktree, both writing `agent_session_id`
and both editing the same files. It holds no database connection of its own either: `Store` is an
actor whose `update` methods re-read inside the actor, so a handler on a background task calls them
directly, and a second `SQLiteDatabase` on the file is the cross-connection sequence race that
`UNIQUE(session_id, seq)` exists to survive rather than to invite.

## 4. What an agent cannot reach through it

Nothing here reads or writes a file directly or changes Git state. Terminal tools can run a
command in the workspace's visible interactive shell. Starting, typing and sending control keys
go through the agent's permission machinery. Reading terminal output uses that same boundary,
because it can contain secrets, and marks that output as untrusted content.

Nothing here opens or closes a tab except the tools whose whole subject that is. `workspace_tab_select`
brings an existing tab forward and will not make one on the way, which is what keeps "go back to the
terminal" from forking a second terminal.

`workspace_archive` runs the app's normal archive lifecycle, including the project archive script.
The worktree is removed; the branch, notes and chat history are kept. Running agents, queued
messages, uncommitted work, local files at risk and failed safety checks refuse the call. There is
no force or branch-deletion argument. Already archived workspaces are a no-op. This tool is not
self-approved for either role: removing a worktree is a question a person answers, and `reveal` can
show candidates before the owner chooses which to archive.

**Its arms are shaped like `workspace_rename`'s, and one of them answers differently.** The owner's
own client takes an exact workspace id from `workspace_list`, is acted on at once, and only answers
success after completion. A workspace agent passes nothing to archive its own: the token says which
workspace is asking, so there is nothing to name and nothing to forge.

**A workspace agent may also name, by `id`, a workspace it started, and no other.** That is the
case that forced the widening: one workspace hands a job to another, the other reports back, and
the one that asked is the one that knows the job is done. Before, the agent asked to clean up could
not (it was a child, and children did nothing) and the agent that started it could not either (it
could only name itself), so the worktree stayed until a person archived it by hand. Parentage is
read off `WorkspaceOrigin.parentWorkspaceID`, which no caller can claim, and any id that is not a
workspace the caller started, real or not, gets the same refusal, so the answer does not confirm
which ids exist. That call is archived at once rather than booked, with no turn excused: the caller
is standing in a different worktree, so nothing it is waiting on is removed, and a turn still
running over there refuses it, which is right, because that agent is not done.

An agent's call on its own workspace is a **request rather than an archive**, and its answer says so in those words.
The agent is standing in the worktree that would be removed, and `AppModel.performArchive` stops a
workspace's agents before git touches a file, so archiving there and then would kill the turn that
is waiting for the answer. Unified Dev books it instead and runs it when that turn ends, whether the turn
ended with a result or with the agent dying. The safety check is then made again from scratch, with
nothing excused: another agent still running in the workspace or a message still queued refuses it,
and the refusal reaches the owner as a notice, because by then there is no agent left to tell. The
first check, made during the call, excuses only the asking chat's own running turn, and never its
queue. See `WorkspaceArchiveSafety`, which is the one place both checks are written.

Nothing a rename touches is on disk. `workspace_rename` writes one column of one row: the branch,
the worktree, the pull request and the directory keep the names they have. That is worth saying out
loud in the tool's own description as well, because a model asked to "rename this workspace" that
believed the branch moved with it would report something to the owner that never happened.

A name is held to what a name is before it is written, by `WorkspaceName.given`: one line, at most
`WorkspaceName.limit` characters, with control, format, private use and unassigned characters
dropped and every run of whitespace folded to one space. `workspace_rename`, `workspace_start`, the
name taken from a task and the name the namer suggests all pass through it. That matters because
the name is printed outside the untrusted-content markers, in the provenance line of a
`workspace_say` envelope and in the refusals that list or name a workspace, and a workspace agent
can set it without asking anyone. Those printers fold the name through the same rule again, in
double quotes, so a row written before the rule existed prints the same way.

Nothing merges. `workspace_merge` **does not merge**: it composes the request Unified Dev's own Merge
button composes and sends it into that workspace's chat as an ordinary message, so the agent runs
`gh pr merge` there, in front of the owner, under whatever permission mode they set. When GitHub
refuses for a conflict or a failed check, that agent resolves it, pushes to the pull request's
branch and merges again, three rounds at most, so the call can publish commits as well as a merge.
Its description tells the caller not to run `gh pr merge` itself when the tool refuses.

`project_add` registers and does not create. The failure it is written against is not a wrong path,
it is a helpful agent: told "add my projects", handed a folder git does not recognise and given a
bare "not a git repository", a model reaches for `git init` and makes a repository where nobody
asked for one, with whatever was lying in the folder as its first commit. The refusal is written to
head that off in words rather than to hope.

A workspace agent may leave the project out, and the new workspace goes in the project it is already in, or
name another, which is how work is handed from one repository to another: an agent in the site's
project that finds the fix belongs in the app starts it there. The owner's client must name one,
because nothing else says which. Either way the name is resolved by `BridgeProjectLookup`, so both
may only name a project Unified Dev already has and both are refused in the same words when the
name matches nothing or matches too much. Naming another project changes nothing else: the
workspace is still `.agent` origin with the caller as its parent, so the caller's ceiling counts it
and it may not start more. The spawn key carries the project only when it is not the caller's own,
so a retry of a call that named none is still recognised as a repeat. `project_list` is open to a
workspace agent for this, because a tool that takes a project name from a caller that cannot find
out the names is a tool that gets guessed at; `project_add`, `project_hide` and `project_unhide`
stay with the owner, because they change the sidebar.

### A subagent is not a started workspace, and the crew tools are about the difference

`workspace_start` cuts a worktree and a branch of its own for the agent it starts, and everything
in the section above is about keeping that agent penned in. `agent_start` does the opposite on
purpose: the agent it starts shares the caller's worktree and the caller's branch, so everything
the crew does lands in one diff and one pull request. The test that says which of the two a caller
wants is how many pull requests they expect at the end, and both descriptions say so out loud,
because a model that picked the wrong one gets either a diff it cannot separate or a branch nobody
asked for. `Crew`'s head argues the whole distinction, including why the code says crew where the
app says subagent.

**The other tool the descriptions have to be about is Claude Code's own Task tool**, and that is
not a documentation nicety: a live test asked for "a subagent called reader" and the model called
Task, because "subagent" is that tool's word and it was already in its hands. A feature a model
never reaches for is invisible, however well it works. So all four descriptions open on the
difference. A Task subagent lives inside one turn, cannot be spoken to and is gone when the turn
ends; one of these gets its own chat and its own row in the sidebar, keeps its context between
turns, takes more work at any time through `agent_say`, and says when it has stopped and what it
last said. The rule given to the model is the useful half: `agent_start` when the work outlives a
single turn or when it will want to talk to the agent again, the Task tool for a one-shot read that
answers inside this turn.

What holds the shape of a crew is three rules, and all three are in `Crew` and `CrewTools` rather
than in the window.

**Depth is one, and it is a column rather than a counter.** A chat with a `parentSessionID` is a
crew member, and a crew member's `agent_start` is refused. That is the same argument
`workspace_start` makes about nesting: a depth number kept beside the thing it describes drifts out of
step with it, and a flat crew has no cycle to deadlock in.

**Three may run in one workspace at once**, counted from the database rather than from anything
held in memory, so a restart cannot lose the count and it cannot drift out of step with the rows
the sidebar draws. Running means `running` or `waiting`: a process holding its turn open on a
question is a live agent in the worktree with a bill attached, while a failed or cancelled one is a
row. Counting the dead would hold a third of a workspace's allowance until it was archived, with
nothing on screen to explain why. Names are counted separately and across the whole workspace,
running or not, because an agent that has finished keeps its conversation and its row until the
orchestrator says it is done with it, and a second agent taking its name would make the transcript
above it read as one agent. `agent_stop` is what gives a name back.

That count is a check followed by an act rather than a lock, and it is worth being honest about
which. The read happens in the handler and the agent is started a hop away on the main actor, so
two orchestrator chats in one worktree calling at the same moment can both be let through. One
orchestrator's own calls are serialised by the bridge, two of them are not, and that second case is
supported on purpose. What the race costs is a fourth agent in the worktree and nothing worse,
which does not pay for a locking scheme across the seam.

**`agent_say` counts too, because waking a stopped agent is a start.** The census leaves a stopped
member out on purpose, so it holds no slot; but a message to one puts a turn back on it. Without
the same count in `agent_say` the ceiling was a formality: start three, stop one, start a fourth,
then say something to the stopped one, and four agents are running on one branch. So a message to a
member that is not currently running is refused with the same sentence `agent_start` gives when the
workspace is full. A message to an agent whose turn is already open is never refused, because it
joins that turn rather than opening a second one.

**There is no sideways.** An orchestrator names which of its crew it is talking to; a crew member
names nobody and talks up, because it has exactly one agent it can talk to. A crew member that does
name a crewmate is refused rather than quietly redirected, and an orchestrator naming an agent
another chat in the same worktree started resolves to nothing, because "its own crew" is
`Store.crew(of:)`. Every message therefore passes through the agent that knows what the whole job
is, and there is no ring of agents to deadlock on one another. `agent_stop` follows the same rule
for the same reason: only the chat that started a member may stop it.

`agent_stop` is not on the destructive side of any of this, and it is how an orchestrator finishes
with an agent rather than only how it interrupts one. It ends the agent if it is still running,
takes its row out of the owner's sidebar and gives its name back for another subagent to use, and
leaves every file that agent wrote and every word it said exactly where they are: the conversation
stays readable. What it costs is work in flight, not work done, which is what its description says
so that a model does not call it expecting a revert.

**Nothing sweeps a finished subagent away, and that is the decision rather than the thing nobody
got round to.** A timer that clears a row can always clear the agent the orchestrator was about to
send more work to, and there is no length of wait that is right for both cases, so Unified Dev sweeps
nothing and the tools say what to do instead. `Crew.tidyHint` is that sentence, written once and
carried into the three places a model reads: the line put in an orchestrator's chat when one of its
subagents stops, `agent_start`'s description, and `agent_list`'s answer, which prefaces it with the
count of how many of the crew have finished so the instruction is about somebody in particular
rather than a line in every answer. An orchestrator that ignores it costs a row in the sidebar and
nothing else, because a finished agent holds no running slot.

A message from a crew member reaches its orchestrator inside `BridgeUntrustedText`, exactly as text
read off a web page does and for the same reason: a subagent is a model that has been reading
files, and what it says back is data rather than an instruction from the person the orchestrator is
working for. See `Crew.message(from:saying:)`.

### Talking to another workspace

`agent_say` stops at the edge of a worktree, and `workspace_start` used to be the last thing an
agent could say to the workspace it started. "Fix this bug in the other repository, release it and
tell me the version" had no way to follow up. Claude Code's own cross-session messaging delivers the
text, and the agent receiving it rightly treats an unverified relay as one and will not merge or
tag on its say-so. `workspace_say` is Unified Dev delivering the message itself.

**Inside one profile it carries the owner's authority, and that is the owner's decision.** An approval step was built
first: the message waited, a card showed the owner the text, and only an approved message arrived as
theirs. It was taken out. Every agent here works for the same person, and the control the owner
wanted is the one every queued message already has: taking it back out before it goes. So the
envelope names the workspace, its id, its project and the chat that sent it, says the message
carries the owner's authority, and says that anything it quotes from elsewhere is still data.

**Addressed by workspace, delivered to a chat, queued like anything else.** The caller names a
workspace by the id `workspace_list` reports, or by a name no other workspace shares. The message
goes into the chat that last wrote to the caller's workspace from there, when it is answering
something, and into that workspace's active chat otherwise. `Store.enqueueWorkspaceMessage` writes
the delivery and a `workspace_messages` row in one transaction. The delivery is what the receiving
chat drains; the row is what the sending chat reads.

**Both ends are drawn, and both agree.** In the receiving chat the message is a periwinkle bubble on
the right, with the owner's turns, because the right means "said to this agent"; the line above it
names the workspace, project and chat. Queued, it is dotted and has Delete, like the owner's own
queued turn, but not Edit or Steer, and its words never go back to the composer. In the sending chat
the `workspace_say` call is drawn as an outlined bubble on the left, "To" the other workspace, saying
queued (with Cancel), delivered and when, or cancelled. The row's `state` is moved inside
`acceptDelivery`, `markDelivered`, `cancelDelivery` and `restoreDelivery`, in the same statements
that move the delivery, so the two bubbles cannot disagree. A cancel through either chat tells the
sending chat.

**Cancel stops at the drain.** Once the drain has claimed a delivery, neither end takes it back:
`Store.cancelWorkspaceMessage` removes a delivery only while it is still pending, and the
receiving transcript refuses its own Delete while that delivery is the one it is dispatching.
`cancelDelivery` still accepts an `uncertain` delivery, which is what an earlier run left behind
when it stopped between claiming a delivery and accepting it, and only the receiving chat can
clear one. The sending chat is told the message has already gone. Deleting an archived workspace
cancels every message still queued into it or out of it, so no bubble in another chat is left
saying queued about a message that will never go, and the bubble there changes on its own rather
than through a message back to the sender.

**The reply path is the same tool.** The envelope ends by naming the id to pass back, and
`Store.latestWorkspaceMessage` routes the answer to the chat there whose message most recently
reached this agent, rather than whichever chat is active there. It counts delivered messages only:
a message still queued has not been read, so nothing can be answering it, and it may yet be
cancelled. A message from the owner's own client says there is no workspace to answer.

**A workspace another agent started may write to any workspace, like every other.** It used to be
narrowed to the workspace that started it and to one whose message had reached it, and that
narrowing went with the child role, for the reasons in section 2.

**"Tell me when you are done" is Unified Dev's job, not the other agent's.** Written into a message,
it was forgotten often enough, and an agent that failed or sat on a permission prompt could not say
so at all, which from the calling side looks exactly like one still working. So `workspace_say` and
`workspace_start` take `notify_when_done`, and Unified Dev puts one fact in the calling chat when
the turn that call caused comes to rest: finished, with the other agent's last message fenced and
cut at 4,000 characters; failed, with the reason fenced the same way; stopped by the owner; blocked
on a permission prompt or a question for the owner; or the workspace archived first. It is the
same delivery `reportToOrchestrator` makes for a subagent, one workspace further out. The promise
is a `workspace_done_watches` row, written in the same transaction as the message, so it survives
a relaunch mid turn, and spent by an `UPDATE ... WHERE notified_at IS NULL`, so it is kept at most
once. A message's watch waits until the message is delivered, so the turn it was queued behind
does not count; a start's watches the new workspace's first chat. A message the owner cancelled is
told nothing more, and a calling chat closed in the meantime is told nothing. The owner's own
client has no chat to tell, so the flag is ignored there and the answer says so. A start
called from the project's orchestrator is watched whether the flag was set or not, because
following what it started is the whole of its job. A workspace started any other way in a project
with an orchestrator, from the create sheet, by another agent's `workspace_start`, from a work
suggestion or from the owner's own client, is announced to the orchestrator as well: its first live
top level chat gets one `workspace_started` report naming the workspace, its branch, who started it and
the task, fenced like the rest, and a start watch on the new workspace's first turn, unless it opened
with no chat or no task, when the report says nothing will follow. The watch is written before the
report, so a report never promises a watch that failed to be written. A seeded preview does not announce. Only creation is
announced; a workspace restored from the archive or archived is not. An orchestrator with no live
chat is told nothing, and a failure to announce never stops the workspace being created.
`Store.announceToOrchestrator` does both writes, `OrchestratorRole.announcedOrchestrator` decides who
is told, and `WorkspaceStartedNotice` is every sentence. The rules and
every sentence are `WorkspaceDoneWatch` and `WorkspaceDoneNotice`, and `Store.settleWorkspaceDoneWatches`
spends the watches and queues the report; the app only says when a turn ended and drains the chat
it was told to.

**Two agents answering each other is a loop, so it is braked.** Each message starts a turn, and an
agent told to answer with `workspace_say` answers "thanks" too. From a workspace, the thirty-first
message to the same workspace inside ten minutes is refused, and so is the same text, whitespace
aside, sent to the same workspace inside that window. Two agents working through something together
send a message a turn for a while and stay under thirty; a loop sends one every thirty seconds to
two minutes and reaches it inside the window. Counted per direction from `workspace_messages`, so a
relaunch does not reset it and the side answering is braked separately from the side asking, with
cancelled messages left out. The refusal tells the model not to retry and to wait for the answer or
tell the owner. The owner's own client is exempt, because a person is typing there. See
`WorkspaceSayThrottle`.

**One thing on the bridge can now be destroyed, and it is a few lines of the owner's own writing.**
`quick_prompt_update` overwrites a prompt and `quick_prompt_delete` removes one, and Unified Dev keeps no
copy of what was there before. Three things hold that in: both are owner only, so the caller is a
client the owner is typing into rather than an agent running for ten minutes unattended; neither is
self-approved, so the call stops and asks a person who is sitting there; and the delete's answer
carries the whole prompt back, name, mark and text, so `quick_prompt_create` writes it again
verbatim, which is an undo that costs one call. The two delivery switches are the exception, and
deliberately: `sends_immediately` and `opens_new_chat` are reported by every one of these tools and
set by none of them, because they say what happens when the OWNER presses a row and a tool that
could arm them would be an agent arranging a turn he never read. A prompt restored by
`quick_prompt_create` comes back as an ordinary one, and the delete's answer says what he has to
turn back on. That last one is what a worktree does not have and
is why archiving is still not here.

A quick prompt deleted over the bridge is deleted exactly as one deleted in the panel is, because
it is the same call. **A built-in stays deleted.** Unified Dev seeds its built-ins once and records the
seed version it reached, rather than reconciling a list against the table, so a prompt the owner
threw away is not read back as one that is missing. Nothing in the four tools writes that recorded
version, so no tool can reseed and none of them can resurrect what it deleted. The one write the
listing can make is the seeding itself, on a copy of Unified Dev whose panel has never been opened, which
is exactly what opening the panel would have done: the tools and the panel have to describe the
same library, or an agent asked to add "Explain changes" writes a second copy of the prompt Unified Dev
is about to insert. See `QuickPromptSeed` and `QuickPromptCall`.

The library is **global**, which is why the two that change it are shaped differently from every
workspace scoped tool. The pane tools came off `.owner` because they act on the worktree the caller
is standing in and that role stands in none; a quick prompt belongs to no worktree, so there is
nothing for the owner's client to be missing and the argument runs the other way. `.workspace` keeps
the two that cannot lose anything, because the owner mostly talks to Unified Dev from inside Unified Dev and
"save that as a quick prompt" is a sentence typed into a workspace chat. It does not get the two
that overwrite and delete: a workspace agent runs unattended, and a change to a global library decided in
the middle of one of those turns up weeks later in a project that workspace had nothing to do with.

`quick_prompt_update` is partial, and its description says so before it is called once, because a
model that reads "update" as "replace" blanks the text every time it fixes a name. A field left out
keeps the value the row holds. `name` passed as an empty string clears the name, which is a state
the panel's own form can produce: the row falls back to showing the start of its text. `text`
cannot be blank, because a prompt with no words in it inserts nothing, and that is the same rule
the form enforces by disabling Save. A call that names no field at all is refused rather than
answered with "nothing changed", because the next call a model makes after those two answers is a
different call.

### Suggesting work instead of starting it

An agent that finds work outside what it was asked to do had two ways out, and neither was right:
say it in the chat, where it scrolls away, or start it with `workspace_start` or `agent_start`,
where nobody decided. `work_suggest` is the third: the agent proposes, the owner disposes.
`workspace_start` and `agent_start` are for work the owner asked the agent to start; everything
else is a suggestion, and both descriptions and this one say so.

A suggestion is a row in `work_suggestions` and a row of its own in the calling chat's transcript,
`MessageKind.suggestion`, written in one transaction, so the card sits right after the agent's call
and survives a quit. It carries a title, one sentence of why, the whole prompt, and a target: this
chat's project, another project Unified Dev has (hidden or not), the path of a repository on this Mac
that is not a project yet, or `owner/repository` on GitHub. The card shows the prompt whole before
anything can start, so nothing starts on text the owner could not read.

**Nothing on the bridge starts a suggestion.** The buttons do: New Workspace goes through
`AgentWorkspaceLaunch`, the path `workspace_start` takes, with the suggesting workspace as
the new one's parent, so that workspace's ceiling counts it; Here goes through `CrewLaunch`, the path
`agent_start` takes, as a subagent of the chat that suggested it, under the same three rules;
Add Project and Start runs the Add Project check first; Open as Draft fills the New Workspace draft.
The press is the approval, and the brakes those tools have apply to it: a refusal puts the card
back with the reason and when to try again. `Store.claimWorkSuggestion` moves the row from pending
to starting in one statement, so two quick presses start it once, and a press that arrives after
`work_withdraw` is refused with "Withdrawn by the agent".

**A card in a workspace an agent started offers Here and no New Workspace.** With one role that
workspace can call `work_suggest` like any other, and New Workspace there would cut a grandchild,
which `workspace_start` refuses off the caller's row. The card is not that tool and nothing would
stop it, so `WorkSuggestionCard.offers` drops the button when the suggesting workspace's row names
a parent. Work in another project, and work in a folder that is not a project yet, offer nothing
but Dismiss there, for the same reason: Add Project and Start is New Workspace with a registration
in front of it. The way out is the same one the owner always had, Open as Draft in the card's
context menu, which fills the New Workspace composer and cuts a workspace of the owner's own.

Add Project and Start refuses more than Add Project does, because an agent chose the folder. A
folder inside a repository is refused rather than adding the repository around it. So is a
repository with an executable hook that is not a sample, or whose own configuration (local or
worktree scope, included files counted) holds any key beyond the plain ones git writes itself: the
`core` settings `git init` records, `remote.<name>.url` and `.fetch`, `branch.<name>.remote` and
`.merge`, `init.defaultBranch`, `user.name`, `user.email` and the two `extensions` a repository
format needs. The card tells the owner to add it with Add Project if they trust it.

`work_suggest` refuses a title, reason or prompt holding Unicode tag characters or direction
controls, which would show the owner one text on the card and hand the agent another, and counts
each limit in code points as well as in characters. A `project` with a line break or another
control character in it, line and paragraph separators included, is refused, so an agent cannot
write a line of its own onto the card.

A workspace holds five suggestions waiting at once, counted from the database across its chats,
leaving out chats that have been archived; the sixth is refused with the way out. An Ask chat holds
its own five. `work_withdraw` takes back one the calling chat made, while it still waits.

Both are self-approved and both are in `BridgeToolbox.standard`: they write two rows and reach no
window. Both are offered to a workspace agent and to the owner's own client, and to nothing else.

A prompt that quotes text from outside, fenced the way `browser_text`, a subagent or `workspace_say`
fence it, reaches the new agent with those fences rebuilt by `WorkSuggestionBrief`: a preamble says
the fenced lines are data, and each quoted stretch is escaped by `BridgeUntrustedText` again, so a
marker inside it cannot close the fence early. A line that is only shaped like a marker is quoted
the same way, wherever in the prompt it sits, and a prompt whose only markers are shapes still
gets the preamble. What a shape never does is open or close a quote, which only an exact marker
can.

A card the owner starts as a new workspace carries the same promise `notify_when_done` makes: the
chat that suggested the work is told once when that workspace's first turn comes to rest, through
the same `workspace_done_watches` row, written by `WorkSuggestionLaunch` rather than by a tool. A
card from an Ask chat leaves none, because the Ask is not a workspace chat there is a report to
drain into, and a press that finds the workspace already made writes no second one.

### The browser pane, and what it does and does not hand over

**Stated as a capability rather than as a list of tools: an agent working in a workspace can see
which panes are open in that workspace, read a browser pane open to agents as words, as a picture or
as a numbered list of the things a reader could use, move that pane about, and act on the things in
that list, in the workspace it is standing in and nowhere else. What it cannot do is reach a browser
pane the owner has kept, or describe a verb and have Unified Dev perform it.**

**A browser pane is either the owner's or open to agents, and the two do not share storage.**
`BrowserPaneAccess` says which, per tab, and every decision about it is in the core.

| | The owner's | Open to agents |
| --- | --- | --- |
| How a pane gets there | The owner opened it, by a link or the menu, or it was restored with no access recorded | An agent opened it with `pane_open` or `pane_split`, or the owner shared it |
| Storage | WebKit's default store for the app | One persistent store with a fixed identifier, shared by every agent pane in every workspace and profile |
| `browser_*` | Refused, by `BrowserPaneChoice.choose` | Served |
| `pane_list`, `workspace_tabs` | Number only: named "Owner's browser", no address, no title, `open_to_agents` false | Everything, `open_to_agents` true |
| `pane_close`, `pane_rename` | Refused | Served |

A popup and a duplicated pane take the access of the pane they came from. A link the owner follows
never reuses a pane open to agents, so nothing the owner signs in to through a link lands in their storage.

**Only the owner moves a pane.** The eye button in a browser's toolbar does it, and no bridge tool
can. Sharing rebuilds the pane on the agents' store and reloads the address there, signed out, since
nothing is copied between the stores. Taking a pane back leaves it blank, because the address it holds
may be one an agent chose, and loading that with the owner's sign-ins is what the separation exists
to prevent. Anything signed in to on the agents' side is within reach of every agent, in every
workspace, which is what the button's help says.

**What this does not hold.** The separation is the bridge's. An agent that can run commands runs as
this user, and what it can read on disk is limited by that user, as section 2 says of the token.

**This section used to say the opposite, and the change is worth reading rather than skipping.**
Until the acting tools were added it said, in prose and with an argument, that the pane could not be
clicked, could not be filled in and could not be scripted, and that the signature of
`BrowserSession.evaluate` taking a `BrowserPageScript` rather than a `String` was the guarantee.
That argument was against **`evaluateJavaScript` as a tool**, and it still holds: a permission prompt
showing a paragraph of JavaScript is a prompt nobody can evaluate, because two lines of it look
reasonable to anybody. What changed is that the same reasoning, followed to its end, produces the
narrow verb rather than nothing at all. There are now five more verbs and still no
`browser_eval`, and the guarantee moved from one signature to the list below. Every line of it has
a test behind it now, and the line says which. The ones that live in the JavaScript are held by
`Tests/BrowserScriptTests`, a second test target that links WebKit, loads fixture pages into an
offscreen `WKWebView` and asserts what each script answers; `./Tools/test-browser-scripts.sh` runs
it, and CI runs it on every pull request. It is a target of its own because `Tests/CoreTests`
depends on `Core` alone by design and because the package `Tools/test-core.sh` writes holds the
line about who may import a UI framework.

**A per-project switch was considered and left out.** The older text promised, for the day this was
done, "a per-project setting, off by default, never self-approved, with the script shown in the
prompt". The script being shown in the prompt is no longer the right shape, because there is no
caller-written script to show. The setting was dropped on the owner's decision of 3 October 2026:
what it would buy is a second barrier in front of an agent that already has to ask for every single
click, and what it costs is a panel in the project settings, a project key, a fresh refusal in five
tools, and the question "why does this do nothing" the first time he forgets to turn it on.
Approval per action is the brake.

**What holds now, and what each line is held by.**

- **There is still no `evaluateJavaScript` and no `browser_eval`.** The scripts are five, written out
  by hand in `BrowserAgentScript`, at compile time, and not one of them carries a character of the
  caller's text in its source. What varies goes in as a named argument of `callAsyncJavaScript`:
  a reference reaches the page as an `Int`, text as a `String` the page can only read as a value.
  `BrowserAgentScriptTests.textNeverReachesTheSource` builds a fill whose text closes a string
  literal and opens a call, and asserts the body never contains it.
- **None of the five is self-approved.** The owner sees and approves every snapshot, every click,
  every fill and every key. What the request names is a reference the page itself gave the agent,
  never a selector the agent invented, because `BrowserAgentReference` parses `e7` and refuses
  everything else, `#submit` and "the delete button" included, which is
  `BrowserAgentReferenceTests`.
- **The scripts run in a content world of their own,** `unified-dev-agent`, which shares the DOM and
  does not share the JavaScript context. The register of references lives there, on a `window` the
  page cannot see, so the page can neither read which elements the agent is holding nor swap one for
  another. `BrowserAddressTests.thePageCannotSeeTheRegister` has the page look for itself, from its
  own button after a snapshot, and read back `undefined`.
- **A reference is only ever resolved against the newest snapshot, and every reference dies at a
  navigation.** Two mechanisms, catching different things: `BrowserAgentHandles.pageChanged()` on
  `didCommit`, for a real navigation, and the script's own prelude comparing `location.href`, for a
  page that changed its address without one. `BrowserAddressTests`, in the browser script target,
  drives the second one off the page's own button: a click that calls `pushState`, `replaceState` or moves the hash leaves the
  next reference answering that it is gone, and a page that stays where it is keeps its register.
  After either, a reference is refused with a sentence rather than applied to whatever now sits at
  that index, and `pointedAt()` requires `node.isConnected`, so an element that has been replaced
  answers that it is gone.
  **What is not promised is that a reference from an older listing of the same page is refused.** A
  second `browser_snapshot` replaces the list, and `e3` then means the third element of the newest
  one, which is the newest truth available; the tools' descriptions say to snapshot again after
  anything that changes the page. Enforcing more than that would mean putting a snapshot token in
  the reference the agent types, and that was not thought worth the spelling.
- **The register never hands out more references than the snapshot printed.** The outline script
  stops collecting at `BrowserPageOutline.elementLimit` and reports the true total separately, so
  the answer can say "the first 400 of 9000" without the other 8,600 being clickable, and
  `BrowserAgentHandles.recorded(count:)` caps at the same number. A snapshot whose answer could not
  be read clears the register rather than leaving the previous page's count standing over the new
  page's elements. `BrowserDrawingTests` puts 405 elements on a page and asserts both halves: the
  listing stops at 400 and says so, and a click on the 401st answers that it is gone.
- **A password is filled and never read.** The snapshot writes `holds 9 characters` where it would
  write a value, and the answer to a fill reports a length. A field counts as a password when its
  type says so, when its `autocomplete` names one, or when the page masks it with
  `-webkit-text-security`, inline or from a stylesheet; it is not required to be an `input`, because
  a masked `textarea` is a field a page really has. **And once a field has counted, it goes on
  counting**, in a `WeakSet` on the same `window` the register lives on, which is what makes a
  page's own "show password" button safe: flipping the type to `text` takes the masking away, so
  nothing on the element says what it was, and before this the next snapshot printed the password.
  That memory dies when the register does, at a navigation or a changed address.
  `BrowserSecrecyTests` is each of those against a real page, including the toggle and the masked
  `textarea`, and asserts the listing carries the length rather than the password. **The gap that
  is left** is a field nothing has ever masked at the moment of a snapshot: masked by a web font,
  or flipped to `text` before the agent ever looked. The owner's decision of 3 October 2026
  is that the agent may write into a password field: the text comes from its own turn and the owner
  approved the action, and refusing to write would leave him typing a password by hand in the middle
  of a test it was meant to run for him.
- **What comes off the page arrives fenced.** The snapshot goes through `BridgeUntrustedText`, the
  way `browser_text` already does, with any line that would read as the closing marker quoted,
  including one that is only shaped like it. Every word the page wrote, its role as much as its
  label and its value, goes through one flattener that drops line breaks, drops the quotation mark
  so nothing can close the quotation it is put in, and caps the length, so a page cannot add a line
  to the listing or grow the answer without bound. The one place a page-written word appears outside
  the fence is the label in the sentence confirming a click, a fill or a key, and that sentence is
  built in `BrowserAgentOutcome` in the core, which says in the same breath that the words are the
  page's own wording and not an instruction. `BridgeUntrustedTextTests` and
  `BrowserAgentOutcomeTests` hold the fence and the sentence, and
  `BrowserClickingTests.theSentenceMarksThePagesWords` carries a page's own words through the real
  script into it.
- **The events are synthetic, so `isTrusted` is `false` on them.** A page that insists on a real
  gesture from a person is not fooled by this, which `BrowserPressingTests` reads back off a page
  along with the key and the number the page sees. That is a limit and not a defect, and it is said
  in the tools' own descriptions rather than discovered: a form that submits on a real Enter may need
  `browser_click` on its button instead.
- **An answer about a page is an answer and not a guess.** A fill reads the field back and reports
  what it is now holding, because a number field, a date field or a field with a format of its own
  discards a value it does not recognise, and "filled it with six characters" about an empty field
  is a lie an agent would act on. A field that cannot be typed into at all, a select or a checkbox
  or a button, is refused rather than filled, and an element the page marks `aria-disabled` is
  refused by the click as well as reported as disabled by the snapshot. `BrowserFillingTests` and
  `BrowserClickingTests` are each of those in a real page: a number field offered "a dozen" answers
  that it is holding nothing, a select answers that it is not a field, and a page that records what
  its own handler did shows the handler never ran.
- **What is still out:** uploading a file, reaching into an iframe of another origin, sending a
  modifier combination, and any verb the caller describes instead of naming. A wait is bounded
  between one and thirty seconds, and running out of time is an answer rather than a failure, so
  nothing here can be made to sit on a page indefinitely.

**The two older scripts are unchanged.** `BrowserPageScript` still holds exactly two cases,
`document.body.innerText` and a scroll, neither carrying a string, and `BrowserSession.evaluate`
still takes a `BrowserPageScript` rather than a `String`. The acting scripts do not go through it:
they go through `callAgentScript`, which takes a `BrowserAgentScript` and the agent's own content
world, for the same reason the older signature was worth having.

**What comes back off a page is marked as untrusted where it arrives.** A page can say anything,
including "ignore your instructions", and a model reading a wall of prose cannot tell which words
came from the owner. `browser_text` answers inside `BridgeUntrustedText`, which names the address,
says the lines are data, and quotes any line of the page that would have read as the closing
marker, including one that is only shaped like it: a different number of rule characters, a rule
drawn with something other than a hyphen, a character that draws as nothing where a space belongs,
or a letter borrowed from another script. That is not a defence and is not described as one:
nothing stops a model that decides to obey the page. It removes the excuse. The picture
`browser_screenshot` returns carries the same sentence beside it, and a browser tab's name and
address are page-written too, so `pane_list` and `browser_read` carry the note as well.

**Nothing here can reach another workspace's window.** There is no workspace argument on any of
them, exactly as with the four older pane tools, so an agent cannot read a page in a window
somebody is working in on the other side of the sidebar.

**Listing never opens a page; the other browser tools do.** A caller names a browser by the number
`pane_list` gives it, counting along the strip. `pane_list` and `browser_read` ask
`CenterTabStore.liveBrowser`, so a listing cannot cause a page to be fetched: a tab restored from
the last launch that nobody has looked at is reported with the address it remembers. Every other
browser tool asks `browser(for:)`, which makes the web view when no pane has drawn it yet. They used
to ask `liveBrowser` as well, and an agent that opened a browser in a tab behind the one in front
was told nobody had opened it until someone clicked the tab. None of those tools is self-approved,
so the owner has agreed to the call, then or by an earlier grant, before the page is loaded.
`browser_go` points the tab at the approved address before the web view is made, so creating it
cannot fetch the address the tab happened to remember. A web view that is not in a window and has
never been measured is given a frame of 1280 by 800 points, because at zero points the page is
laid out at nothing and a picture of it is empty. `browser_screenshot`, `browser_scroll`,
`browser_text` and the four acting tools that point at an element wait up to ten seconds for a load
in progress first, which is `BrowserPaneCommand.readsPage`. **`browser_wait` is the one tool on this
list that says `false` there, and deliberately:** waiting is the whole of what it does, it has a
ceiling of its own that its description promises, and letting the ten second wait run in front of it
would make a call asking for two seconds take twelve, report an elapsed time missing the first ten,
and never look for its phrase while the page was still streaming it.
`browser_go` takes the two schemes `pane_open` takes and refuses the rest, through the same reading,
so neither door will render `file:///` in the owner's window on a model's say-so.

**And no self-approved tool draws one.** A web view that is drawn fetches its page, with whatever is signed in to the agents' browser, and
`browser_go` asks before doing exactly that to an existing tab. So the three self-approved tools that put things on the screen stop short of it.
`pane_open` opens a browser behind the tab in front and ignores `focus`, because `PaneOrder` gives a
browser no focus whatever the caller asked for, and `PaneOrder.placement` keeps the tab in front
where it was. No `BrowserSession` exists until `BrowserTabView` draws the tab, so nothing is fetched
until the owner clicks it, and the browser tools that need a live page refuse it until then; its
confirmation tells the agent so. A workspace with nothing in front has nothing for a browser to sit behind, and that call is
refused rather than drawn. `pane_split` would draw its pane at once beside the calling chat, so it
opens a browser blank and refuses a `url`, and the agent points it with `browser_go`, which asks.
`workspace_tab_select` refuses any tab that holds a browser, alone or as one pane of a split,
because `WorkspaceTabSelection.withoutMoving` says so before anything is selected. An agent that
wants a page in front of the owner asks him to click it.

### The strip, and what a tab tells a caller

`pane_list` and `workspace_tabs` report one window and are not two versions of one tool. The first
flattens a workspace into panes, which is the shape the browser tools need, because the question
they ask first is "which of the reader's browsers do you mean" and a browser is a pane wherever it
is sitting. The second is the strip itself, because that is the shape a person speaks in: "go back
to the chat about the parser", "bring the notes forward". A flat list of panes has nothing in it
that is a tab, since a split contributes two rows and neither of them is the thing the reader would
click.

A tab is one entry of that strip, and it is one of five things: a chat, a terminal, a browser, the
review or the notes. The first three a workspace can have several of; the last two it has exactly
one of each. A tab can also have been split, in which case it owns a small tree of panes and the
other things living in them have dropped out of the strip. That last part is the one piece of
window furniture a caller mostly does not need, so it is reported and kept small: a split tab lists
what it has absorbed, kind and name, and nothing else. Ratios, axes, which half has the keyboard
and the pane ids themselves are all left out, because there is no tool that takes any of them.

What each kind says is what Unified Dev is already holding:

| Kind | What the tab reports |
| --- | --- |
| `chat` | Which CLI drives it, the `sessions` row's own state, whether a turn is running, how many messages |
| `terminal` | The directory its shell was started in, and whether a shell has been started at all |
| `browser` | The toolbar: where it is pointed, what the page calls itself, whether it is loading, and the number the `browser_` tools take |
| `review` | The file it is on, or that it is on the whole change |
| `notes` | How long the note is, and never a word of it |

**The cases were chosen against a rule rather than by taste: nothing in a listing may cost a
subprocess or a request.** The two temptations were a terminal's live working directory and what is
running in it, and both mean asking tmux, inside a call an agent makes at the top of every turn. So
the tab says where its shell started and says out loud that it does not know the rest, which is a
true small answer instead of a plausible large one. For the same reason nothing here creates:
`CenterTabStore.liveBrowser` is asked rather than `browser(for:)` and `TerminalSessionStore.hasShell`
rather than `terminal(for:)`, so a listing cannot fetch a page or fork a shell in a worktree nobody
had opened.

**A tab is named by a number or by its name, and never by its id.** The number is its place in the
strip counting from 1, which is `BrowserPaneReport.number`'s argument applied again: a uuid is a
handle a model cannot read, cannot repeat to a person and can carry in from somewhere stale. The
title is accepted as well, which the browser tools deliberately do not do, and the difference is
that a browser's name is the page's own `<title>` while a tab is the one thing in this window a
person names out loud. A title that two tabs share is refused with their numbers rather than
resolved to the first, because guessing there means selecting a tab the caller did not name.

That title is whatever the strip draws, down to the fallback: a chat nobody has titled reads
`Untitled` in the strip, in the Go to Tab menu and over the bridge, because `workspace_tab_select`
takes back the name `workspace_tabs` handed out. One function answers it for all three,
`CenterTabStore.title`, and it was three functions with two different fallbacks.

**`workspace_tab_select` cannot create a tab, and that is the refusal it was written around.** The
tempting shape is "select it, and open it if it is not there", which reads as helpful and is how an
agent asked to go back to a terminal ends up forking a second one beside the one it meant. A name
nothing answers to is a refusal carrying the strip, ten tabs and a count of the rest, so the next
call can pick off it without a workspace of thirty tabs spending the whole refusal listing them, and
`pane_open` stays the only door a tab is opened through on request. `canvas_show` is the one other
caller that makes a tab, and it does not go through `NewPane.open`: it asks `CenterTabStore.showCanvas`,
which swaps the file of the workspace's one canvas or adds that canvas when there is none. Selecting
a chat also makes it the workspace's active conversation, which is not an extra effect: it is what
clicking that tab does, through the same `WorkspaceTabsStore.select` the click goes through.

### Which branch a workspace starts on

`workspace_start` offers the choice the new workspace draft offers, and it is the draft's own choice
rather than a second one written for the bridge. The draft offers it as the New branch from and
Existing branch sections of its starting point popover; over the socket it is two arguments, named
by `WorkspaceSourceTab`, and `AgentStartSource` is the translation between them.

| Argument | The tab it is | What happens to a commit |
| --- | --- | --- |
| `base_branch`, or nothing | Create new branch | It lands on a new branch, and merges into the branch that was named |
| `existing_branch` | Continue on existing branch | It lands on the branch that was named, and merges when that branch does |
| `pull_request` | Continue on existing branch | It checks out the pull request and keeps its GitHub identity, base branch, checks and merge controls |

Nothing said is a new branch from the project's default branch, which is exactly what the tool did
before there was a choice, so every caller written against the older tool keeps working. Naming
both arguments is refused rather than resolved to one of them: they are opposite in effect, and a
call that asked for both has not decided.

**The second one is here because the first one answers the wrong question about somebody else's
work.** Told to look at a colleague's branch, the tool could only cut a fresh branch off its tip,
so the worktree opened identical to that branch and the Changes tab drew nothing. It was right and
it was useless. That is the bug `docs/start-from.html` was written about, arriving a second time
through the other door.

The branch is found in the project before anything is cut, and both ways of not finding it are a
sentence rather than a failed start. A name that is not there is answered with the names that are,
which is the list the picker would have shown somebody who could see one. A branch something else
is already sitting on is refused with what has it, git's own worktrees included rather than only
Unified Dev's rows, because git allows one worktree per branch and the alternative is git exiting 128 in
the middle of a start. Both refusals end by offering `base_branch` on the same name, which is a
different intention and Unified Dev does not take it on a caller's behalf.

A pull request can be named by number, `#number` or GitHub URL. Unified Dev resolves it through `gh` and
hands the resulting `WorkspaceCheckout.pullRequest` to the same path as the new workspace draft. This is
different from naming its head branch. The pull request checkout records the PR number and base,
which lets the inspector show the existing checks and merge controls instead of offering to create
a new pull request.

### How many a caller may start

`WorkspaceStartAllowance` holds all three answers in one switch, and they are one rule with one
variable in it, which is **how much a workspace costs the caller to ask for**.

| Caller | Brake |
| --- | --- |
| The new workspace draft and a Shortcut | None. Each is a deliberate gesture per workspace; a `unifieddev://` link and the Services menu only open the draft |
| A workspace agent | Eight workspaces it started that are not archived, at once |
| A project's orchestrator | Sixteen workspaces it started that are not archived, at once |
| The owner's own client | Six starts in fifteen minutes |

The two brakes are shaped differently on purpose. The workspaces an agent started are work it is waiting on, so
what matters is how many are alive at once and a ceiling is right. The owner is a person whose
workspaces accumulate over weeks, so a ceiling would refuse the eleventh workspace of a busy
fortnight, which is ordinary use; what is not ordinary is the rate. None of these numbers is a safety
limit. Six worktrees and six agents is already real money, and the point of all three is that somebody
notices at six, at eight or at sixteen instead of at forty.

An orchestrator's ceiling is higher because starting workspaces is the whole of its work.
`AgentWorkspaceLaunch.overAllowance` reads `isOrchestrator` from the parent's row on every call, so
nothing an agent passes or says can raise it. A workspace that stops being the orchestrator is held
to eight at its next call, and when it already holds more nothing is archived for it: it starts
nothing until it holds fewer than eight.

All three are counted from the database rather than kept in memory, so they survive a restart. The count
is a reading and not a reservation: a workspace's row is written only after `git worktree add` has finished,
so two starts at the same moment can both pass on the same number, and an orchestrator can end up
holding seventeen of sixteen. Nothing is taken back; the next start is refused until it holds fewer than the ceiling.

Every start is deduplicated by a digest of the call, because a model retries and a retried spawn
cuts a second worktree. A repeat answers with the workspace that already exists and a note saying
so, rather than with a second one.

## 5. Which questions Unified Dev answers for itself

**A bridge call raises a permission question like any other tool call.** Measured: on claude
2.1.238 under `acceptEdits`, calling `whoami` produced an ask for
`mcp__unifieddev-workspace-bridge__whoami` and the turn stopped until it was answered. Being an MCP tool
does not exempt a call from the permission machinery, which was half the reason the bridge is MCP
rather than a CLI the agent shells out to. The first `workspace_start` in a project stopped a
workspace agent's turn on an ask, and with nobody watching that workspace the turn sat waiting and died
`cancelled` when the app quit, having started nothing. **A feature whose first use hangs unless
somebody happens to be looking is a feature that does not work.**

So `BridgeToolApproval` names the tools Unified Dev answers for itself:

| Self-approved | Not |
| --- | --- |
| `whoami`, `workspace_start`, `pane_open`, `pane_split`, `pane_close`, `pane_rename`, `workspace_rename`, `pane_list`, `workspace_tabs`, `workspace_tab_select`, `chat_list`, `chat_read`, `workspace_diff`, `browser_read`, `media_show`, `canvas_show`, `canvas_read`, `canvas_edit`, `canvas_render`, `canvas_comment_resolve`, `quick_prompt_list`, `reveal`, `agent_start`, `agent_say`, `agent_list`, `agent_stop`, `workspace_say`, `work_suggest`, `work_withdraw`, `project_list` | everything else |

It is a list rather than "anything with our prefix", so a tool added later is opted in by somebody
thinking about it rather than by inheriting a decision made before it existed.

Answering is not a shortcut round consent, because **Unified Dev is on both ends of this question**. It
wrote the tool, it minted the token, it knows which workspace is asking, and it enforces every
limit itself: the handler refuses a caller whose workspace was itself
agent-started, and eight, or sixteen for a project's orchestrator, is the ceiling. There is nothing for a person to weigh that
Unified Dev has not already decided, and the ask carries no information a person could act on beyond "an
agent would like to use Unified Dev". None of that is true of the tools the agent brings with it: `Bash`,
`Write` and `Edit` reach outside anything Unified Dev knows about, and nothing here touches them.

`canvas_show` is on it because it shows one file that is already in the caller's own worktree, through
the same containment rule the document preview applies, with no network. It writes one thing: a path ending in
`.udcanvas` that does not exist yet is created as a blank document with one frame, and any folders it needs, still
inside that worktree, because a canvas has to exist before `canvas_edit` can change it. A blank file in the caller's
own worktree costs nothing a person would weigh. An orchestrator has `Edit` and `Write` taken away, so there the same
call writes nothing and is refused, by the same guard as `canvas_edit`. A turn with nobody watching must not hang on a
question about showing a file to the person it is for, and there is nothing for a person to weigh that the tool has
not already decided.

`canvas_read` is on it for the same reason: it reads one document that is already in the caller's own worktree,
through `CanvasFile`, and writes nothing. It goes through the workspace's document model rather than the tab, so
it answers with the tab closed.

`canvas_edit` and `canvas_render` are on it for the same reason, each decided on its own. `canvas_edit` does write,
but only the one canvas document in the caller's own worktree that `CanvasFile` resolves, through the same keeper an
owner edit goes through: every update or delete must carry the revision the agent read, so an edit the owner made in
the meantime wins and the agent is told, and every call is one undo step the owner can take back. A turn with nobody
watching must not hang on a question about editing a file, and the keeper refuses what a plain file write would not
notice: a document under a hold. An orchestrator has `Edit` and `Write` taken away, so `canvas_edit` is on the list
`OrchestratorToolGuard` refuses, with a reason of its own, and the tool refuses it too. `canvas_render` reads the
document and draws one frame, and writes nothing.

`canvas_comment_resolve` is on it for its own reason. It writes the state and the answer of one comment in one canvas
document in the caller's own worktree, through the same keeper and the same holds as `canvas_edit`, and it changes
nothing the owner drew and no undo step. A comment that goes unanswered only because a turn with nobody watching hung
on a question is the failure the tool exists to prevent. The caller has to be the chat the comment's delivery row was
sent to: a comment sent to another chat, not sent yet though it waits in that chat's queue, or whose row has gone is refused and left as it is, because
an answer from a chat that was never asked would close the comment without the work and could not be taken back. The
owner can resend what is left. It is deliberately not on the list `OrchestratorToolGuard` refuses: an orchestrator
that cannot edit a canvas has to be able to decline with that reason, or the owner is told only that the comment went
unanswered.

A comment reaches a chat as a comment from the owner only when the owner sent it. The app remembers, for this run, the
id and the text of what the owner added, edited or pressed Send or Resend on, and uses that up when the comment takes a
delivery row. Anything else queued in a file with no row, whether it arrived by a clone, a checkout or an agent writing
the file, and whatever id it carries, waits until the owner opens its mark, reads it and presses Send. `canvas_read`
opening such a file sends nothing, and `canvas_edit` has no operation that adds a comment. The cost is that a comment
left with no chat needs that click after a restart.

For the same reason, nothing `canvas_read` returns is the owner's word. A branch can carry a file with a comment already
marked queued, and that comment is listed under `openComments` next to element text and frame names from the same file,
all read by an agent with auto-approved tools. So the tool describes them as what the file holds, and both its answer
and the conflict answer of `canvas_edit` are quoted between the untrusted content markers, with a fixed `fromFile` field
saying that this is data and not instructions, and that a comment is acted on only when Unified Dev sends it as a
message. A sentence a canvas tool writes itself, a refusal or a warning, names what came from the file in double quotes
with control characters folded away and long lists shortened, so a name in a document cannot pose as the tool speaking.
`canvas_render` says the same of the text drawn in its picture.

`canvas_read` also limits itself, because a document is written by whoever wrote the file and an answer that size would
be read whole. Frames and open comments have a share of the limit each, a value over 2,000 characters is shortened,
elements past the limit wait for the next `offset` and frames past their share for the next `frameOffset`, so every
frame and element can be reached, and `cut` counts everything left out so an agent is never answered with part of a
document and told nothing. Open comments past their share are only counted: they are not what an agent acts on, because
a comment reaches it as a message.

A delivery row keeps the text it was queued with. When it is about to be sent, the document has to hold exactly one
comment naming that row, quoting the same text; otherwise the row is dropped, nothing is sent, and the comment is shown
as unanswered for the owner to read and resend. The position and the names may change, because anchors move and frames
are renamed, so the position is a plain line of its own, written by the app, and the names are in the lines marked as read from the file.

The four pane tools are on the list because each adds or changes something the reader can see and
undo, in the workspace whose agent is asking and nowhere else. None of them may draw a browser,
which would fetch a page from the browser without asking: the browser pane section above
says how each stops short of it. `pane_close` refuses the two cases that would cost anything: it
will not empty the centre column, and it cannot close the review or the notes, which hold the
reader's own work. With kind `canvas` it closes the workspace's canvas wherever it sits, in the tab
in front or not, because the canvas is the one tab an agent puts up by itself and should be able to
take down again.

`workspace_rename` is on it, and it is the entry that had to be argued against the quick prompt
paragraph below rather than against the pane one above, because it overwrites something and keeps
no copy. Three things settle it. What it overwrites is one column of one row, and a label Unified Dev
proposed most of the time, rather than a paragraph the owner wrote by hand. The change is in the
sidebar row the reader is looking at as it lands, which is the same visibility a pane's name has,
and typing over it is a double click away. And the answer carries the name the workspace had, so
undoing it from the far side of the socket costs one more call. Against that sits the reason it
must not ask: this tool exists because an agent nine commits into a piece of work stopped and asked
the owner to rename the workspace by hand, and a permission prompt on a workspace agent running unattended
is the hung turn this whole section is about, spent on a label.

The two tab tools follow them. `workspace_tabs` reports the same furniture `pane_list` reports in
another shape, all of it on the screen in front of the reader and none of it the contents of a
page, a diff or a note. `workspace_tab_select` is `pane_open` with less in it: that one both makes
a tab and brings it to the front and is already on this list, so asking before an agent may bring
forward a tab that already exists would cost a hung turn and protect nothing. Both hold a browser
back, and for the same reason. What it changes is which tab the reader is looking at, and one click
puts it back. The cost that is real is interruption, and it is answered in the tool's description
rather than by a prompt: a person may be typing in the tab in front, so the tool says to ask before
pulling them out of it.

**The seven browser tools split, and the line between them is the chrome.** `pane_list` and
`browser_read` report the strip and the address bar: what is open, what it is called, where each
browser open to agents is pointed, whether it is loading. Every fact of that is on the screen in front of the owner
already, none of it is the contents of a page, and they have to be callable unattended because they
are the first call of any turn that then does something useful. The other five are off the list, in
two groups. `browser_reload`, `browser_go` and `browser_scroll` change what the person is looking
at: a reload can lose what they had half typed into a form, a navigation is a request made with
whatever is signed in to the agents' browser, and a scroll moves the page under somebody who is
reading it. `browser_screenshot` and `browser_text` carry the page itself into a model's context,
which is to say off this machine, and a page he is signed into is his own data. Unified Dev cannot tell a
dev server's front page from an administration screen, so it does not try: it asks, and the person
who can tell answers.

`reveal` is on it, and it is the one entry whose argument runs the other way from the paragraph
below. It is called by the owner's own client, so the owner IS sitting there, and asking would put
a question in front of somebody who has just said out loud "show me those". It creates nothing,
archives nothing and touches no file: what it costs is a glance, and the way back is a click.

`work_suggest` and `work_withdraw` are on it because neither starts anything. One writes a card the
owner reads before anything can happen, and the other takes back a card the same chat wrote. An ask
on either would put a question in front of the owner about whether he may be asked a question.

**The four crew tools are on it and they stand or fall together**, because a crew that can be
assembled and not spoken to is worse than no crew at all. An orchestrator that has to stop and ask
the owner before it may talk to agents it started itself is exactly the hung unattended turn this
section is about, and here there is a second cost: an agent is sitting at the other end of the
unanswered question with a bill running. None of the four reaches outside the workspace the caller
is already in. They read and write the `sessions` rows of one worktree, the caller's own token says
which worktree that is, and there is no argument on any of them that could name another.

Against the paragraphs above about what is deliberately off this list: none of the four destroys
anything. `agent_start` adds a chat to the sidebar in front of the reader, which is the visibility
a pane has. `agent_say` puts a message in a chat the owner can read and answer. `agent_list` reads.
`agent_stop` ends a turn the caller started itself and takes that agent's row off the sidebar,
leaving the conversation and every file the agent wrote where they are.
And what a person would otherwise be weighing has already been decided in the core, before the
window is asked for anything: the depth limit, the ceiling of three and the name rule are all in
`Crew`, which is the same argument `workspace_start` is on this list under.

`project_list` is on it: it reads Unified Dev's own database, changes nothing, and is the call a
workspace agent makes before naming another project to `workspace_start`, so an ask there would
hang the turn that is about to hand work on. The other project tools are not on it, and that is
deliberate rather than an omission: they change the owner's sidebar, and they are called by the
owner's own client, where the owner is by definition sitting there to answer.

`quick_prompt_list` is on it and the other three quick prompt tools are not, which is the same test
applied four times. The listing is offered to `.workspace`, so it can be called by an agent running on
its own, and it reads the owner's library and changes nothing in it: the ask would carry nothing for
a person to weigh and an unanswered one would hang the turn for no gain. `quick_prompt_create`
writes a row into a panel nobody is looking at, rather than putting something in front of the
reader the way a pane does, so it is worth one ask; the cost of that ask is the hang described
above, and it is accepted because the tool is only ever called on the owner's own instruction, in
the chat they typed it in, which its description says out loud. `quick_prompt_update` and
`quick_prompt_delete` take words the owner wrote by hand and there is no undo, which is the clause
`BridgeRole.owner` is written against.

`workspace_merge` draws the line one step further out. It destroys nothing, it sends a turn. But
what that turn leads to is a call to a server other people share, and unlike a worktree there is
nothing on the far side to restore. **Unified Dev answering its own permission question there would be
Unified Dev deciding to publish, which is the one decision it has never had.**

A self-approved ask still leaves a settled row in the transcript, saying what happened and who let
it through. "Allowed automatically" with no reason is the thing that makes people distrust an app's
permission model.

### What an orchestrator's commands get

The project's orchestrator gets three answers to a shell command, and `OrchestratorToolGuard` picks
one on every ask, reading the role from the store each time.

| Answer | What gets it |
| --- | --- |
| Unified Dev allows it, once, before anyone is told | Every clause is on `OrchestratorReadList`, `OrchestratorShellParser` found nothing it cannot read literally, any directory named in the ask is the worktree, and a `cmd` beside the command names the same command |
| Refused | Any clause is a git verb in `OrchestratorShellJudge.gitVerbs` |
| Left for the agent and the owner | Everything else, including every command neither list names |

The list is closed, so a command nobody thought about is never answered by Unified Dev, and so is
every flag. `ls`, `cat`, `grep`, `head`, `tail`, `wc`, `pwd` and `echo` each take a closed set
of flags, single letter ones running together as `-la` for `ls`, `cat`, `grep` and `wc`, and anything else is asked: a flag that
follows a file or waits on it, one that reads a second file, `--libxo`, which on macOS can load an
encoder from a path. A word that is not a flag must name a path inside the worktree for the six
that read files, so an absolute path or a `..` is asked, because a read nobody saw could otherwise
reach any file this user can open. The rule reads the words and not the disk, so a symbolic link
inside the worktree is followed, and a directory changed by an approved `cd` moves what a relative
path names. `echo` takes `-n` and any words. A word given to `git` that is not a flag is held to the same
rule, because `git diff` with a path outside the repository compares files as if `--no-index` had
been given. `git` is a list of verbs, each with its own closed set of flags, and `gh` a list of verbs sharing one closed set, because git
has `--output` on a verb that otherwise reads, `-c` and `-C` that bring in other configuration, and
`gh pr view --web` opens a browser in front of the owner. Nothing after a `--` may start with a dash,
because git treats it as a file while a word by word reading would take it for a flag, and `--format`
and `--sort` need their `=` on `git branch` and `git tag`, because the bare form consumes the next
word and `--format --list new` creates a branch. `gh` takes no `--repo` and no URL, and `gh repo view`
is not on the list, since each can name a host, and a read that ran unasked could then carry what it
read to that host. `gh` takes `--json` and no `--jq` or `--template`, because both filter
languages can read the process environment, and no `--search`, because its text goes to GitHub as
written, so a read could carry whatever the agent had read before it. The remaining filters and a `gh`
positional also reach the API of this repository's host, which is what is left open: they take a
word rather than a query, and no flag on the list names another host. Neither is `gh run watch`, `--watch` or `--interval`, nor `tail -f`, because each holds the call until
what it follows ends or the Bash timeout cuts it off. `gh api` is not on it, since one flag turns it into a write. Neither is `sed`,
`find`, `awk`, an interpreter, or any form of `git stash` or `git apply`.

The parser works over Unicode scalars rather than Swift characters, so a `\r\n` or a combining mark
cannot hide an operator inside one grapheme. A clause counts as plain only with nothing the shell
would reinterpret: an unquoted character outside letters, digits and `_-./,:=+@%~` stops it, and so
does `$` or a backtick inside double quotes, a subshell, a lone `&`, or a redirection to anything but
`/dev/null`, `/dev/stdout`, `/dev/stderr` or another descriptor. A descriptor before `>` is one digit,
because zsh reads a longer number as an argument and bash does not. One after `>&` is a number or a
lone `-`, because zsh takes anything else, a dash in front of a number among it, for a file name and
writes it. The appending form takes no descriptor at all, because zsh reads what follows it as a
file. A word that begins with `~` or `=`, or has `~` straight after a `=` or a `:`, stops it too,
because the shell replaces those with a home directory or a command's path, and quotes with nothing
in them do not change where a word begins. `sh -c`, `cd`, `git -C` and a leading
`VAR=value` are never answered either, which is the cost of the list.

A listed read is answered on the way in, the way a self-approved bridge tool is: no question is
stored, nothing tells the window, and no `workspace_say` watch is spent on it. Git's own configuration
still applies, so `diff.external` or `core.fsmonitor` in the repository's config runs under a listed
`git diff` or `git status`. Writing that config takes an approved command in this workspace, or an
agent in another, which already runs as the same user.

What happens to the rest depends on the agent:

| Agent | A command off the list | Another server's MCP tool |
| --- | --- | --- |
| Claude, run by Unified Dev | `permissions.ask` raises it and the owner answers | `mcp__*` in `permissions.ask` outranks an allow rule in the owner's settings: measured on claude 2.1.309 with a stdio server and an allow rule for its tool, the tool ran unasked without that entry and raised `can_use_tool` with it. A stored approval does not answer it |
| Claude in a terminal chat | Claude asks in the terminal, for listed reads too, because no runner sits between them | The same `permissions.ask` |
| Codex | Runs in the read only sandbox, and reaches the owner only when it asks to leave it. It is answered only when the request is a command request about running that command, names the command a known item runs, and carries no field beyond those known to change nothing about what runs; anything else goes to the owner, including a field added by a later version of Codex. A command Codex wraps in its own shell is never answered | No approval request exists for an MCP tool call, so nothing here judges one |
| Grok | Asked on every call | Asked, and so are the bridge's own tools, since only Claude's runner answers those |

The same judge decides the Run button on a code block, which only the owner presses. In an
orchestrator a command on the list runs at once, and any other command first opens an alert showing
the whole command, continuation lines included, the folder it runs in and that it may change files;
it runs only when the owner confirms, and cancelling runs nothing. A character that would not show
or would reorder the text, such as a bidi override or a zero width space, is spelt out as `[U+code]`
in the alert, which then says how many it holds; what runs is the command as written.
`CodeBlockLaunch.of` takes that decision and `CodeBlockConfirmation.answer` the one after it. Outside an orchestrator the button runs what the reply showed, as it always has.

### Running commands without asking

A project's settings carry a switch, **Run commands without asking**, in the Workspaces pane. It is
on by default: a project with nothing stored counts as on, and a value the owner saved, on or off, is
kept as saved. `OrchestratorUnaskedCommands.parse` takes that decision. Off changes nothing above. It belongs to one project: another project's
orchestrator does not inherit it, and a workspace that is not the orchestrator is not affected.

On, a shell command that would have stopped for the owner is judged by `OrchestratorUnaskedJudge`,
which reads the words of the whole command, including what sits inside a compound, a command
substitution, a here document, `eval`, `sh -c` and programs known to run other programs:

| Answer | What gets it |
| --- | --- |
| Refused | Anywhere in the command: a git verb in `OrchestratorShellJudge.gitVerbs`, `gh pr merge`, `gh pr checkout`, a redirection to a file, a program on the list of those that write files, or one whose flag says it writes or edits in place |
| Unified Dev allows it, once | Every program in the command is on `OrchestratorUnaskedPrograms.runWithoutAsking`, or is `git`, `gh`, `find`, `sed` or `awk` used only to read, and nothing in it is refused or left for the owner |
| Left for the owner | Everything else: any program off that list, builds, test runs, scripts in the worktree, interpreters, `curl` and every other network tool among them, a runner that does more than wrap (`ssh`, `sudo`, `npx`, `watch`, `tmux` and the like) whatever it runs, a command the judge cannot read, a command name or git verb only known at run time, a script on standard input or inline, an environment variable set for a command, git flags that bring in other configuration, a git verb it does not know, a `gh` command off its short list, `gh` deleting or setting something, a `gh` read that waits on what it follows (`gh run watch`, `--watch`, `--interval`), unterminated quoting, an ask with a field it does not know, or nesting and work beyond a fixed limit |

The refusal outranks the other two, so one refused clause refuses the whole command. Tools other
than the shell are untouched: file edits and terminals stay refused and another server's MCP tool
still asks. The orchestrator still does not implement, and the refusal says so to the model.

**The judge is its own reading of shell grammar and not the shell.** A construct it cannot place asks,
but a construct it misreads can pass, so its refusals are a net rather than a wall, and they are not
what makes the switch safe to turn on.

**The list is closed.** A program passes only when Unified Dev names it, and it names programs that
read: listing and reading files, searching and filtering text, paths, the date and the machine's own name.
`git` and `gh` pass only for their reads, by the verbs and flags above, and the `gh` verbs they share with
the read list are one table, `OrchestratorReadList.ghVerbs`, with `gh repo view`, `gh repo list` and
`gh label list` added here, since the judge checks the host they name. A listed name passes only bare or
in one of the system's own directories, `/bin`, `/usr/bin`, `/sbin`, `/usr/sbin`, `/usr/local/bin` and
`/opt/homebrew/bin`, so `./git` or `tools/cat` committed to the project asks. git asks when it is pointed
at another repository: `git -C`, a command that also changes directory, `find -execdir git`, a shell
call whose working directory is not the worktree, and `git ls-remote` with an address rather than a
remote's name, since another repository's own configuration can run programs and an address can
name any host. `sed` passes only with scripts that print, delete or substitute with `/`, and `awk`
asks when it loads an extension or runs a file. `tail -f` asks, as `gh run watch` does, because it
holds the call until what it follows ends.

A wrapper that only changes how a program runs, `env`, `time`, `nice`, `timeout`, `nohup`, `command`,
`builtin`, `stdbuf`, `xargs` without a replacement string, `noglob` and `nocorrect`, is judged by the
program it runs. `OrchestratorUnaskedWrappers` knows each one's options and which of them take a value,
so a value is never taken for the program, and an option it does not know asks: `env -P`, `env -C` and
`time -o` among them. A listed program whose arguments make it write a file, `uniq` with an output
operand, `tree -o`, `tree -R` with `-H`, `file -C`, and `tar` told to delete or join archives, is refused,
and one told to run another program or reach a host, `sort --compress-program`, `rg --pre`,
`rg --hostname-bin`, `tar -F`, `tar --info-script` and an archive named with a host, asks. `xargs` adds
arguments from what it reads, so it passes only in front of a listed program outside
`OrchestratorUnaskedPrograms.steeredByTheirArguments`. Everything else asks rather
than being refused, so nothing that worked before is blocked: it comes back to the owner once.

**Paths stay in the worktree.** A command that passes the judge passes only if
`OrchestratorWorktreeReach` also finds that every path it can name stays inside the orchestrator's
worktree, and that limit holds for the read list above as well, switch on or off. It reads every
argument, the value after `=`, `@` or `:` in one, the words of a nested shell and of a command
substitution, and the target of each change of directory, and resolves each one on disk with
`WorktreePathResolver` before deciding, so a link inside the worktree is judged by where it really
leads and `~` by the home it names. The search pattern of `grep` and `rg`, the script of `sed` and
the endpoint of `gh api` are not paths and are left out, and only where the words before them leave
no doubt which word that is. A change of directory passes only with one operand that names an existing
directory inside the worktree explicitly, from `/`, `./` or `../`, so that no search path the shell
keeps can send it elsewhere, and only when no link below that directory leads out. The orchestrator's
Claude is launched with `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` set, so each command starts from the
worktree again; Codex and Grok name the directory of every command, and it has to be the worktree.
Anything whose path is only known at run time asks: an expansion handed to a program that reads files,
a glob that matches a link out, a program fed its arguments by another, a list of files to check read
from a file, and the flags that make `find`, `grep`, `rg`, `tree`, `ls`, `du` and `diff` follow links
as they walk. Outside the worktree, or in doubt, it asks rather than refusing.

The judge reads words and runs nothing, and a `gh` read or `git fetch` reaches GitHub, or the host a
remote names, with what it is given. That is the cost of the switch being on, along with the one
the settings footer names: text planted in a file or an issue the orchestrator reads can choose which of
those reads run, and the owner does not see them first. Each one still leaves its tool row in the
transcript. The Run button on a code block is not affected.

**The setting is read on every ask.** `SessionGrants` reads it from the store each time it judges a
command, so turning it off applies to the next ask, in a chat already running, with no restart.

| Agent | With the switch on |
| --- | --- |
| Claude, run by Unified Dev | Honoured, through `can_use_tool` |
| Claude in a terminal chat | **Not honoured.** No runner sits between Claude and the owner, so it keeps asking in the terminal, as it does for listed reads. Honouring it would mean launching with a wider permission, which could not be withdrawn until the chat restarts |
| Codex | Honoured for a command request about running what its known item runs, the rule that already holds answers there, and a command Codex wraps in its own shell is judged by what it wraps. A request outside that rule goes to the owner. A command inside the read only sandbox never asks, so none of this touches it |
| Grok | Honoured, through `session/request_permission`. An ask with a field the guard does not know goes to the owner |

**Only the app writes it.** It lives in the `settings` table of the app's database, under
`OrchestratorUnaskedCommands.key(repoID:)`, and never in a settings file, because a file in a worktree
is one an agent can edit. `SettingsLoader` knows no such key, no bridge tool writes settings, and
`make lint` holds that the one call that saves it stays in the settings pane, and that `setSetting` appears
nowhere in `Sources/Core/Bridge`, in `AppModel` or in a file that serves a tool. `OrchestratorUnaskedReachTests`
calls every bridge tool's handler, in every role it is served to, with every field set to one of six values
naming the switch or its owner, then with only the fields it requires and with every field, read from their
names and filled with the quick prompt and suggestion ids that exist, and reads the switch back from the store
after each call, starting from an off the owner saved, so that it is still off. It then cuts, sets up, archives, restores and opens a workspace with settings files planted in
the project, which is where those paths read them, and loads the worktree's planted files through
`SettingsLoader` directly, reading the switch back after each step. What it does not reach: the app's own
closures behind the tools `AppModel.bridgeToolbox()` adds, which the suite replaces with stubs, so for those the
handler is proven and the closure is held only by the lint above, one file deep; and the home directory's
settings files, which the core reads through the same `SettingsLoader` the suite calls directly. `make lint`
refuses an app tool the suite does not build. `sqlite3` and `defaults` are left with the owner. The database is still a file this user owns, so a program already running
as this user can open it, which no app can prevent.

### Asking to fix a pull request on its own

A project's settings carry a switch in the Workspaces pane that lets the app send the request behind **Ask to fix**
when a pull request has a conflict with its base or a failed check. It is off by default, and only those two
states are covered. `PullRequestAutoFix.decide` takes the decision and `PullRequestFixColumns` holds what was
already tried, per head commit and reason, with at most three in a row per pull request.

It holds to the same rule as the switch above: it lives under `PullRequestAutoFixSetting.key(repoID:)` in the
`settings` table, `make lint` keeps the one call that saves it in the settings pane, and
`OrchestratorUnaskedReachTests` reads it back after every bridge tool. The same limit applies, since a program
already running as this user can open the database.

Anything the decision cannot establish counts as no: the fork flag, the pull request's author, the signed in
account and the author GitHub attributes every commit on the head to. That attribution comes from what a commit
declares, so it narrows who can put text in front of the agent and does not close it. A failed check's log is still text the agent reads with nobody reading it first.

The request goes through `submitAppRequest`, as the click does, into the chat the click would choose, and it never
creates a chat or changes the tab on screen. A turn in progress holds it back rather than queueing it, the chat
is read again immediately before it goes, a chat in Bypass permissions never receives one, and the conflict request
carries only the app's own steps, leaving out `.unifieddev/conflict-instructions.md`. The checks it names are re-read
and have to belong to the head the attempt was claimed for. What the agent loads for itself from the repository,
such as its own instructions file, is outside what this request controls.

## 6. How each CLI is told the bridge exists

Two completely different mechanisms, both verified against the installed binaries.

**Claude Code** reads a JSON file named by `--mcp-config`, written mode 0600 in a 0700 directory,
one per session, rewritten from scratch at every process start because the token in it is minted
per launch. **A file, never the inline JSON string the same flag also accepts**, because argv is
visible in `ps` and an agent runs `ps` through its own Bash tool as ordinary behaviour. Never
`--strict-mcp-config` beside it: that flag shuts every other MCP configuration out, which is right
for `WorkspaceNamer` and wrong for a chat, where the user's own servers have to survive. Measured
on 2.1.238 by running a live turn, because `claude mcp list` rejects `--mcp-config` outright and
nothing short of a turn exercises it: `system/init` listed the user's own servers alongside Unified Dev's,
all connected, and the tool reached the model as `mcp__unifieddev-workspace-bridge__whoami`, hyphens
carried through.

**Codex** takes `-c mcp_servers.<name>.…` overrides carrying the same values inline. Unified Dev already
runs one app-server process per chat, so a per-process override is a per-session registration, the
same as Claude Code's per-start argv. Never `--strict-config` beside it: a different flag from
Claude Code's, the same trap, and it makes Codex refuse to start on a user config holding anything
the build does not recognise.

The server name is `unifieddev-workspace-bridge`, and it is **a correctness requirement with a test
behind it** rather than a convention. Codex `-c` overrides do not shadow a colliding
`mcp_servers.<name>` entry, they deep-merge it leaf by leaf: against a config holding a user's own
server called `unifieddev`, overriding `command` and `env` produced Unified Dev's binary launched with the
user's `args` and the user's `env` key still present, and `codex mcp list` reported that chimera as
one healthy server with no warning at all. There is no `-c` form that replaces a whole entry. So
the only defence is a name nobody would type, and the failure it prevents does not look like a
naming problem when it happens.

The owner's own standalone registration is a third thing, under a **different** name derived per
copy of the app, and `AGENTS-INTEGRATION.md` is where that half is written down: what
`claude mcp add` accepts, why the scope is `user`, and why the name is neither `serverName` nor one
constant for every copy of Unified Dev.
