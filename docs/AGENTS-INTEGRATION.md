# Agent CLIs

Ground truth for the Agents settings screen, read off this machine on 2026-08-18. Verified, not
guessed. Anything not listed here should be treated as unknown rather than invented.

## Security rule

`~/.claude.json` and `~/.codex/auth.json` contain live credentials: OAuth access tokens, refresh
tokens and possibly an API key. Unified Dev reads them ONLY to show non-secret, derived facts (email,
organisation, plan, auth method, expiry). A token must never be rendered in the UI, written to a
log, put on the pasteboard, or included in an error message. When a field is missing, say
"unknown", never fall back to printing raw file contents.

## Detection

| Agent | Executable | Version command | Observed output |
| --- | --- | --- | --- |
| Claude Code | `claude` | `claude --version` | `2.1.234 (Claude Code)` |
| Codex | `codex` | `codex --version` | `codex-cli 0.147.0` |
| Grok | `grok` | `grok --version` | `grok 1.0.24 (68e414c661e3) [alpha]` |
| Cursor | `cursor-agent` | `cursor-agent --version` | not installed here |
| OpenCode | `opencode` | `opencode --version` | not installed here |

Resolve the executable through `Shell.which(_:)`, which already augments PATH for a GUI launch.
The observed output is the shape to parse and not a version to match: both installed CLIs move
weekly, and the two figures above were already a release behind a fortnight later. Two of the five
are not installed on this machine, so "not installed" is a first-class state and has to look
deliberate, not broken.

## Claude Code

Account facts live in `~/.claude.json` under `oauthAccount`. Relevant keys, all optional:

- `emailAddress`, `displayName`, `organizationName`
- `organizationType` (observed `claude_max`), `organizationRateLimitTier` (observed
  `default_claude_max_20x`), `billingType` (observed `stripe_subscription`), `seatTier`,
  `organizationRole` (observed `admin`)

The plan's name is one decision, `ClaudeAccountFiles.plan`, and every screen that names a plan reads
it. It takes the subscription and the tier from `oauthAccount` first, because the CLI refreshes that
object from the server, and from `claudeAiOauth` in `~/.claude/.credentials.json` only for a field
`oauthAccount` lacks, because that file can stay untouched for weeks while the plan moves. The
subscription limits the tier: `AgentAccountReader.claudePlan` lets `*_max_20x` read as Ultra and
`*_max_5x` as Max only on a `claude_max` subscription or when no source names a subscription, so
Team, Enterprise and Pro keep their own names whatever tier they carry. The login method is that name in a sentence: "Claude Ultra account".
The usage panel asks the same decision and falls back to `get_usage` only when neither file answers:
that answer carries `subscription_type` and, in the schema shipped with CLI 2.1.309, no tier, so on
its own it reads a 20x account as Max. A `subscription_type` of `null` means an API key or third-party
session, which names no plan whatever account is on disk. With `ANTHROPIC_API_KEY` or
`CLAUDE_CONFIG_DIR` in the session's environment the default files do not describe that session, so
the panel reads the answer alone.
An `ANTHROPIC_API_KEY` in the environment means API key auth instead, and takes precedence in
what is displayed. Config file to offer for opening: `~/.claude/settings.json` (a symlink into
the user's dotfiles here, so resolve symlinks before revealing it).

Login command: `claude auth login`. Agent sign-in runs in an embedded terminal sheet, using the
same `LoginTerminalSession` as GitHub sign-in. It launches the detected executable directly,
without controlling Terminal.app or requiring Automation permission. The sheet supports retry,
cancellation, and copying the command to run elsewhere. Account details refresh when the command
exits and when the sheet closes. Signing in with another account changes the CLI's shared login.

### Claude in Chrome

The CLI's Claude in Chrome integration drives the owner's own Chrome, with its sign ins, through
the Claude extension. It is off unless `--chrome` is passed: with no flag the `system/init` event of
CLI 2.1.322 lists no `mcp__claude-in-chrome__*` tool, even with `tengu_chrome_auto_enable` set in
`~/.claude.json`. With the flag the same event lists twenty such tools and a `claude-in-chrome`
entry in `mcp_servers` with `"status":"connected"`, under `-p`, under `--strict-mcp-config` and next
to the bridge's `--mcp-config` alike. That was measured against an API endpoint that refuses every
connection, so the init event arrived and no turn was paid for.

When the integration cannot load the turn still runs and the server is simply missing from
`mcp_servers`. Two cases were measured: an `ANTHROPIC_API_KEY` in the environment, because the
integration needs a claude.ai sign in, and a `CLAUDE_CONFIG_DIR` with nothing in it. Whether the
extension is installed cannot be read from disk instead: the CLI writes the native host manifest
into every Chromium browser's `NativeMessagingHosts` whether or not the extension is there, and the
Chrome profile holding the extensions is refused to other processes by privacy protection.

So the switch is the owner's, in Settings > Agents on the Claude Code row, stored as
`agent.claudeCode.chrome` and off by default, because these tools open tabs in the owner's browser.
The choice is part of `AgentRunnerFingerprint`, so turning it either way retires a chat's running
agent on the next message sent to it and starts one with or without `--chrome`. An orchestrator
never receives the flag, because these tools would act in signed in tabs that its tool guard does
not cover: `ClaudeChrome.launches` refuses it when the agent is built, reading the role the way
`orchestratesAtLaunch` does, which counts an unreadable workspace as an orchestrator. The init event is the discovery: `ClaudeChromeNotice.missing` compares what the process
was launched with against what loaded, and the runner stores one notice row per running agent saying why
the tools are absent. A server still `pending` is not reported. A chat run in the terminal gets the
same flag through `interactiveArguments`, read when the terminal launches it. A workspace an
orchestrator starts is an ordinary workspace and gets the flag under its own permission mode.

## Codex

`~/.codex/auth.json` keys: `auth_mode` (observed `chatgpt`), `OPENAI_API_KEY` (null here),
`last_refresh`, and `tokens` with `access_token`, `refresh_token`, `id_token`, `account_id`.

The readable facts are claims inside `tokens.id_token`, a JWT. Split on ".", base64url decode the
SECOND segment, parse as JSON. Do NOT verify the signature and do not pretend to: this is display
only, and the CLI is the thing that actually authenticates.

Claims: `email`, `name`, `exp` (expiry, seconds since epoch), and a nested object under the key
`https://api.openai.com/auth` holding `chatgpt_plan_type` (observed `prolite`),
`chatgpt_account_id`, `chatgpt_subscription_active_until`, `organizations`.

So: Provider `openai`, Plan from `chatgpt_plan_type` (title case it), Auth from `auth_mode`
(`chatgpt` reads as "ChatGPT login", `apikey` as "API key"), Account from `email`.

`exp` is not read as the state of the session, and nothing read from this file is. The token it
dates lasts about an hour and the CLI refreshes it silently, so reading it said the session had
expired under a session that worked. Whether a login still stands is asked of the CLI itself,
through `codex login status`, and the answer is what the account card shows.

Config file: `~/.codex/config.toml`. Login command: `codex login`.

## Grok

Account facts live in `~/.grok/auth.json`, a map of issuer keys to credential objects. Relevant
keys, all optional, on each credential object:

- `email`, `first_name`, `auth_mode`, `expires_at`

`key` and `refresh_token` are live credentials and must never be rendered. `refresh_token` is read
all the same, for its presence alone: `expires_at` in the past means only that the hourly token
aged out, and the CLI refreshes it silently, so the sign-in warning is held back while a refresh
token is there. A file holds one credential object per issuer, and the one read is the first by
sorted key that carries a name or an email, so two sign-ins do not make the reading wander between
launches.

This is the file-read verdict that the Codex section above says is the wrong way to judge a session,
and Grok keeps it for a reason worth writing down: `AgentAccountLiveness` has no question to ask
Grok. `codex login status` and `claude auth status` answer for the other two, which is why their
state is asked rather than read; `grok models` does print "You are logged in with grok.com" or
"You are not authenticated", so the question exists, but nothing wires it up yet. Until it is, the
warning here can still be wrong in the one way the Codex line was: a refresh token present but dead
reads as a session that stands. Wiring `grok models` into `AgentAccountLiveness` closes that and
makes Grok offerable in the same move, since its isolation doubt is gone.

An `XAI_API_KEY` in the environment means API key auth instead, and takes precedence in what is
displayed when no auth file is present. Config file to offer for opening: `~/.grok/config.toml`.

Login command: `grok login`.

## Cursor and OpenCode

Not installed here, so nothing about their auth files is verified. Detect the binary and show the
version if present. Do NOT invent an auth file format for them: show "Connected" only when there
is real evidence, otherwise show that the CLI was found and leave the account block out. Cursor's
config directory is `~/.cursor` (exists here, holds `hooks.json`). OpenCode's is `~/.opencode`
(absent here).

## A second account per process

Read off this machine on 2026-10-24, with Claude Code 2.1.309 and Codex 0.157.0 installed, Claude
Code's keychain rows again on 2026-11-08, and the
Grok column on 2026-11-07 with Grok 1.0.70, which the first reading could not reach because the
binary was absent. This is the other half of the detection table above: not where the session lives,
but whether a second one can be pointed at per process, and what happens to a turn already running
when it changes. Where the paragraphs below say "both CLIs" or "neither CLI" they mean Claude Code
and Codex, which were driven at length; what was asked of Grok is the paragraph under the table and
nothing more.

| | Claude Code | Codex | Grok |
| --- | --- | --- | --- |
| Variable that moves the config directory | `CLAUDE_CONFIG_DIR` | `CODEX_HOME` | `GROK_HOME` |
| Where the session lands | the login keychain, per directory (below) | `$CODEX_HOME/auth.json` | `$GROK_HOME/auth.json` |
| Where the identity lands | `.claude.json` beside the config directory for the default account, inside it for any other | the same `auth.json` | the same `auth.json` |
| Second session per process | yes, total isolation | yes, total isolation | yes, one home at a time; parallel processes not driven |
| Keeps the login in the keychain | yes | no, unless its keyring mode is on | no |
| Enumerates or switches accounts | no subcommand does either | no subcommand does either | no subcommand does either |

Grok was measured on 2026-11-07 with Grok 1.0.70, which the earlier reading could not do because
the binary was absent. `grok du` under a fresh `GROK_HOME` reports `Disk usage for $GROK_HOME` and
creates that directory, so the variable moves the home. The login follows it: `grok models` answers
"You are logged in with grok.com" under the real home and "You are not authenticated" under the
fresh one, in the same shell and seconds apart. That second answer is also what rules the keychain
out, since a login read from a shared keychain would have reached the fresh directory too. No
`auth.json` is written until a login happens there. `grok login` and `grok logout` are the only auth
subcommands; neither lists accounts nor switches between them.

Where Claude Code's login goes was measured again on 2026-11-08 with Claude Code 2.1.309, with a
stand-in `security` first on `PATH` and a throwaway `HOME`, so that no real entry was read. Under a
`CLAUDE_CONFIG_DIR`, a login lives in the login keychain, in two generic password entries:
`Claude Code-credentials-<digest>` for the OAuth session and `Claude Code-<digest>` for a managed API
key. The digest is the first eight hex digits of the SHA-256 of the value of the variable in Unicode
NFC, with no other normalising: a trailing slash or a symbolic link gives another digest. The
account attribute is `$USER`, or the login name when that is unset or empty, or `claude-code-user`
when the result holds anything but letters, digits, `.`, `_` and `-`. `claude auth status` answered
`loggedIn: true` from a stand-in entry under exactly that name and false under any other, and
`claude auth logout` deletes both entries. The default account has no digest, and is never touched.

Removing a Claude Code account deletes those two entries of that account's directory, after its
folder, through `AgentAccountRemoval`, and an entry that cannot be deleted is named to the owner.
The rule is the CLI's and can change with it, so a later version may keep its login under a name this
one does not reach.

This reading wrote no `.credentials.json`; the code still reads one where a folder has it. The
paragraphs that follow are the reading of 2026-10-24.

Both CLIs were driven with an empty config directory and with one holding nothing but the copied
session file. Empty answers "not logged in" while the default directory keeps answering that it is;
the copied session file alone is enough to answer that it is logged in. Claude Code's only lock is
`$CLAUDE_CONFIG_DIR/.claude.json.lock`, inside the directory, so two directories share no lock and
three processes ran in parallel without contention. In that reading neither CLI read the keychain,
which the measurement above contradicts for Claude Code. `codex doctor` reports
`auth storage mode: File` here; the binary also carries a keyring mode, which is off on this machine
and therefore unmeasured, so the mode has to be read rather than assumed.

Two measured facts make `claude auth status` the wrong thing to ask. Its identity comes from the
environment before the config directory: a directory holding no identity at all still answered with
the real email and organisation until `CLAUDE_CODE_USER_EMAIL`, `CLAUDE_CODE_ACCOUNT_UUID` and
`CLAUDE_CODE_ORGANIZATION_UUID` were removed from the environment, and `Shell.baseEnvironment`
passes the whole of the app's environment to its children. And `loggedIn` means present and
unexpired, not usable: a forged, invalid token answered `loggedIn: true` with a subscription type,
because the plan is read out of the file rather than from the server. So Unified Dev reads the
identity out of the directory itself, through `AgentAccountIdentity`, and never asks the CLI who it
is. `AgentAccountHome` is the directory, and `AgentAccountHome.identityPath` carries the one
asymmetry above.

What this does not buy, and what Unified Dev does with it today. Neither CLI lists accounts, so there
is nothing on the machine to enumerate: an account can only ever be a directory something already
knows about, and sweeping the disk for credential files to discover more would be hunting for
secrets. Whether an account still works cannot be known without using it. And a config directory is
fixed at `exec`, so changing the account of a live session means relaunching the process with
`--resume`: the turn in flight is lost and the next one runs on the new account.

That was written before accounts shipped, when Unified Dev read exactly one directory per CLI and
had no list to choose from. It creates a directory per account now, points a launch at one through
`CLAUDE_CONFIG_DIR`, `CODEX_HOME` or `GROK_HOME`, and offers the list wherever an account can be
chosen; what is written above is why it cannot go further than that, not a description of what it
does. The spend screen still groups by the directory a transcript sits under, which is why it can
show spend from a config directory that has since been changed or removed, as historic spend under
no account it knows.

## What Unified Dev can actually run

Claude Code, Codex and Grok. The stream-json protocol in `PROTOCOL.md` is Claude Code's and
`AgentRunner` speaks it; the JSON-RPC app-server protocol in `CODEX.md` is Codex's and
`CodexRunner` speaks it; ACP over `grok agent --no-leader stdio` in `GROK.md` is Grok's and
`GrokRunner` speaks it. All three answer to `SessionRunner`, and `AgentKind.canRunWorkspaces` is
the one place that decides which backends a chat can be started on. Cursor and OpenCode are
detected and configurable and neither has a runner, so neither is offered anywhere a chat is
started. The UI must say so plainly rather than implying a connected CLI is a usable backend.

## Adding a backend

For model discovery, add a source to `AgentModelSource.live`. It returns `AgentModel` values to
the composer, Settings, defaults resolution and workspace bridge. Keep protocol decoding and
ranking in the backend, and use `AgentModelCache` for concurrent fetch sharing, expiry and retry.
The shared model keeps hidden entries available for resolving stored ids while excluding them
from new selections. Model ids and effort ids remain the CLI's own strings.

A source does not have to be the CLI process. Claude Code has no command that lists models, so
`ClaudeModelSource` reads `additionalModelOptionsCache` out of `~/.claude.json`, which the CLI
rewrites on startup from what the server told it, and merges that with the four aliases every
install takes. `docs/PROTOCOL.md` records the shape as measured. A model the account cannot use
yet arrives carrying `unavailable`, which is the server's own reason and is shown beside the name
rather than dropped, because hiding it is what leaves somebody asking where their new model went.

An additional backend still needs an `AgentKind`, a `SessionRunner`, runner construction and its
protocol and permission adapters. Sharing discovery does not imply that cancellation or session
resuming work the same way. Cover those behaviours in the backend's runner tests; the shared
cache and selection rules are covered by `AgentModelCacheTests` and `AgentModelTests`.

## Registering Unified Dev in a client the owner runs themselves

Measured on claude 2.1.241 on 2026-08-23, by running the commands.

`claude mcp add [options] <name> <commandOrUrl> [args...]` takes `-e KEY=value` repeatedly and
`-s, --scope <local|user|project>`. `claude mcp add-json <name> <json>` exists as well and takes
the whole server object as one JSON string, so both shapes are a single copyable line. Unified Dev uses
`add` rather than `add-json`, because the JSON has to be quoted for the shell as well as escaped
for JSON and the result is unreadable in a settings pane, while the `add` form reads as a sentence.

The three scopes are not interchangeable and only one of them is right here. `local` is this
project on this machine, kept in `~/.claude.json` under the project's own key. `project` writes a
`.mcp.json` in the working directory, which is meant to be committed and shared with everyone who
clones the repository. `user` is the top level of `~/.claude.json` and applies to every project on
the machine. Unified Dev's coupling belongs to the owner and to no repository, so it is `user`, and that
is also the only one of the three that cannot end up in a commit carrying a live token.

The server is registered under a name derived from the running copy of Unified Dev: `unifieddev` from the
owner's install, `unifieddev-dev` from `Tools/dev-build.sh`, and anything else from the same table that
decides which Application Support directory a build may open, slugified. See
`BridgeRegistration.ownerServerName`.

It is deliberately not `unifieddev-workspace-bridge`, the name Unified Dev's own per-session `--mcp-config`
uses. That file is additive over `~/.claude.json` rather than replacing it, so a shared name would
put two entries called the same thing in one client: an agent Unified Dev launched inside a workspace
would meet its own session token and the owner's standalone token under one name.

It is also deliberately not one constant for every copy of Unified Dev, which is what it was until the
name was derived. `claude mcp add` replaces an existing entry of the same name and says nothing
about it, and `--scope user` is one file for the whole machine, so Unified Dev and Unified Dev (Dev) both handed
out a command claiming the same entry: pasting one silently evicted the other. Deriving the name
from the same table as the database directory means two builds can only collide here if they were
already sharing a database, in which case they share the token beside it too.

Nothing rewrites an entry left over from before that change. Somebody who ran the older command
still has `unifieddev-owner-bridge` in `~/.claude.json`, and no copy of Unified Dev answers to that name any
more, so nothing here recognises it as its own. The Settings pane says so and offers
`claude mcp remove --scope user unifieddev-owner-bridge`.

A session already running does not pick the server up. Start a new one.

The command is offered in two places and generated in one. `BridgeRegistration.ownerAddCommand`
builds it; `CommandLineOffer` draws it, the warning about `.mcp.json` included, for both the
welcome window's command line step and Settings > Command Line. The welcome step is where somebody meets
it, because nobody browses a settings tab they do not know exists, and the pane is where they go
back for it and where Regenerate lives. The step is offered only when there is something to offer:
`BridgeUserRegistration` reads the `mcpServers` table at the top level of `~/.claude.json` and
compares the entry under this copy's name against the shim path, socket and token it would hand
out today. Anything but a match is offered, an unreadable file included.

### The one thing Unified Dev does write there

The entry holds an absolute path to the shim inside the bundle, it is written once, and nothing
re-derives it. The owner moved Unified Dev from `~/Applications` to `/Applications` and every agent
started from his own terminal failed from that moment, saying the bridge was down and naming a
path that no longer existed. Per-session registrations were fine throughout, because
`BridgeRegistration.shimPath` derives the shim from the running executable each time; only the
durable entry went stale.

`BridgeUserRegistrationRepair` puts that one string back, on launch, and touches nothing else. It
rewrites only an entry under **this copy's own** name whose `UD_BRIDGE_SOCKET` and
`UD_BRIDGE_TOKEN` are exactly the pair this instance mints, whose `command` names a file called
`bridge`, and where that path no longer exists. The socket and token pair is the proof of
authorship: the socket comes from the database path through `TmuxSessions.fingerprint` and the
token is minted beside that database, so no other copy of Unified Dev can produce it. Anything else,
including the legacy `unifieddev-owner-bridge` entry, an entry somebody aimed at another Unified Dev on
purpose, and an entry whose shim is still installed, is left exactly as it was. The write is
atomic and puts the file's mode back, because it holds a live OAuth token.

The token is not refreshed by the repair. A move cannot make it stale, and a token that disagrees
means either that the entry was not minted here or that Regenerate was pressed and never
re-pasted, which is a revocation to leave standing. Both of those already show up as
`notRegistered`, so the command goes on being offered and one paste fixes them.
