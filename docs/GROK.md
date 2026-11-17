# The Grok ACP protocol

Ground truth, captured from `grok` 1.0.24 on this machine on 2026-09-08. Headless
`--output-format streaming-messages-json` looks like Claude Code's stream-json and is a trap:
one prompt then exit, and no wire for permission questions. Unified Dev drives `grok agent --no-leader
stdio` instead, which is ACP JSON-RPC, the same class of protocol as Codex's app-server.

## How Unified Dev invokes it

```
grok agent [--always-approve] [--model <id>] [--reasoning-effort <level>] --no-leader stdio
```

`--no-leader` is load-bearing. Without it a Unified Dev chat can attach to the owner's interactive TUI
leader. `GROK_DISABLE_AUTOUPDATER=1` is set in the child environment so update banners cannot
land on stdout.

Working directory is the worktree. Input is JSON-RPC on stdin, output JSON-RPC on stdout. stderr
is tracing and is not merged.

`clientCapabilities` is sent empty. Advertising `fs` or `terminal` makes the agent ask Unified Dev to
read files and run commands; Unified Dev is not that client. Grok has its own tools.

## Handshake

1. Client `initialize` with `protocolVersion: 1` and `clientInfo`.
2. Server replies with `agentCapabilities` (including `loadSession` and `sessionCapabilities.resume`)
   and `_meta.modelState` listing models and each model's reasoning efforts.
3. Client notifies `initialized`.
4. Client `session/new` (or `session/resume` with the stored id) with `cwd`, `mcpServers`, and
   `_meta.yoloMode` / `_meta.autoMode` / `_meta.permissionMode`.
5. Server replies with `sessionId`. Unified Dev stores it as `Session.agentSessionID`.

Model and effort after that travel as `session/set_config_option` with
`value: { "value": "<id>" }`, which is what Grok's own docs show and what a composer chip change
uses on the next turn without restarting the process.

## A turn

`session/prompt` is held open until the turn ends. Unified Dev therefore must not wait on it inside
`send`: the reply is an event, and a two minute timeout would kill a real turn. Updates arrive as
`session/update` notifications:

- `agent_message_chunk` / `agent_thought_chunk`
- `tool_call` / `tool_call_update`
- `usage_update`
- `available_commands_update` (ignored)

`session/cancel` is a notification. Stop answers pending permission requests as cancelled, then
sends it.

## Usage limits

The menu bar reads the subscription's quota from its own short lived process, outside any
session: `initialize`, then the extension request `_x.ai/billing` with empty params, and the
process is stopped. The leading underscore is part of the name; `x.ai/billing` answers
"Method not found". No `authenticate` is needed, the cached sign in is enough. Measured on
grok 1.0.70:

```json
{"config":{"creditUsagePercent":100.0,
  "currentPeriod":{"type":"USAGE_PERIOD_TYPE_WEEKLY",
    "start":"2026-11-01T13:01:35.239+00:00","end":"2026-11-08T13:01:35.239+00:00"},
  "prepaidBalance":{"val":0},"isUnifiedBillingUser":true,
  "billingPeriodStart":"2026-11-01T13:01:35.239+00:00","billingPeriodEnd":"2026-11-08T13:01:35.239+00:00"},
 "subscription_tier":"SuperGrok Lite"}
```

`GrokQuotaAdapter` reads it as one window: `creditUsagePercent` is the fraction used, the period
type names the window (`weekly`), its start and end give the length, and the end is the reset.
`subscription_tier` is shown as the plan.

The handshake and the request each get `GrokQuotaSource.timeout`, because the poll waits for every
agent and one silent Grok would hold back the others. A CLI that answers the request with `-32601`
does not offer it and shows no card. Any other failure draws Grok as not having answered.

A preview with no Grok account chosen does not ask at all. Grok has no default home for a preview
to redirect, so asking would read the owner's own login.

## Accounts

A Grok account is a directory, and every process Unified Dev starts for it, the chat, the quota
request, the sign-in terminal and the status question, carries that directory in `GROK_HOME`.
`grok login` there writes its own `auth.json`, and `grok models` there says whether it holds a
login. `docs/AGENTS-INTEGRATION.md` has what was measured.

## Permissions

`session/request_permission` is a server-to-client request. The payload is a tool call plus
options (`allow_once`, `allow_always`, `reject_once`, `reject_always`). Unified Dev maps those onto its
existing prompt rather than drawing a fourth UI. An option the agent did not list is never
invented: a missing match is answered as cancelled.

## MCP

ACP `mcpServers` on `session/new` is additive over `~/.grok/config.toml`. Unified Dev registers
`unifieddev-workspace-bridge` there as a stdio server, `env` as an array of `{name, value}` objects.
The owner's own client is a separate `grok mcp add --scope user` command, for the same reason
Claude Code's is `--scope user`.

## A turn stopped by the usage limit

Grok sends no quota event over ACP, and no usage-limit stop has been captured. `stopReason` becomes
the result's `subtype` and `message` its `summary`, with no field that marks a limit.
`TurnStopCause.ofLastTurn` answers `.other` for Grok.
