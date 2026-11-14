# The Antigravity ACP protocol

Ground truth, captured from `agy` 1.5.9 (the Antigravity CLI, Homebrew cask `antigravity-cli`) on
this machine on 2026-11-14, with a Google account on the "Antigravity Starter Quota" tier. Every
message quoted below was sent or received over the wire; anything not measured is said to be.

## Why Antigravity and not Gemini CLI

Gemini CLI 0.68.0 was measured first and refuses a personal Google sign in. `gemini --acp` answers
`initialize`, but `session/new` fails with `-32000` and `gemini -p` with `IneligibleTierError`,
`reasonCode: UNSUPPORTED_CLIENT`, tier `free-tier` ("Gemini Code Assist for individuals"): "This
client is no longer supported ... please migrate to the Antigravity suite of products". No turn can
run through it on that account, so Unified Dev drives the Antigravity CLI instead, which serves the
Gemini models and more under the same sign in.

## How Unified Dev invokes it

```
agy acp [--dangerously-skip-permissions]
```

`acp` is a subcommand, not a flag, and `--stdio` is its default transport. The Homebrew wrapper
sets `AGY_CLI_DISABLE_AUTO_UPDATE=true` before it execs the binary; Unified Dev sets it in the child
environment as well, so a binary installed some other way cannot print an update banner on stdout.

Working directory is the worktree. Input is JSON-RPC on stdin, output JSON-RPC on stdout, one
object per line. `clientCapabilities` is sent empty, as for Grok: the agent has its own tools.

There is no `--model` on `acp`. The model, the thinking level and the mode all travel as
`session/set_config_option` after the session opens.

## Handshake

1. Client `initialize` with `protocolVersion: 1`, `clientInfo` and empty `clientCapabilities`.
2. Server replies with `agentInfo: {"name":"Antigravity ACP Server","version":"1.5.9"}`,
   `agentCapabilities` with `loadSession: true` and `sessionCapabilities` naming `resume`, `close`,
   `load`, `list` and `additionalDirectories`, and four `authMethods`: `oauth-personal`,
   `oauth-business`, `gemini-api-key` and `agent-platform`. Unlike Grok, `initialize` carries no
   models.
3. Client `session/new` with `cwd` and `mcpServers`. No `_meta` is needed.
4. Server replies with `sessionId`, `models`, `modes`, `configOptions` and
   `_meta.antigravity.tier`, then sends `available_commands_update` and a `usage_update` with
   `used: 0` and `size: 1048576`.

The `session/new` reply, trimmed:

```json
{"sessionId":"5361ec1e-...",
 "models":{"availableModels":[{"modelId":"gemini-3.8-flash-high","name":"Gemini 3.8 Flash (High)"},
   {"modelId":"gemini-3.8-flash-medium","name":"Gemini 3.8 Flash (Medium)"},
   {"modelId":"gemini-3.8-flash-low","name":"Gemini 3.8 Flash (Low)"},
   {"modelId":"claude-sonnet-4-6","name":"Claude Sonnet 4.6 (Thinking)"},
   {"modelId":"claude-opus-4-6-thinking","name":"Claude Opus 4.6 (Thinking)"},
   {"modelId":"gpt-oss-120b-medium","name":"GPT-OSS 120B (Medium)"}],
   "currentModelId":"gemini-3.8-flash-high"},
 "modes":{"currentModeId":"default","availableModes":[{"id":"default"},{"id":"accept-edits"},{"id":"auto"},{"id":"plan"}]},
 "configOptions":[{"id":"model","currentValue":"gemini-3.8-flash","options":[...]},
   {"id":"thought_level","currentValue":"high","options":[{"value":"low"},{"value":"medium"},{"value":"high"}]},
   {"id":"mode","currentValue":"default","options":[...]}],
 "_meta":{"antigravity":{"tier":{"name":"Antigravity Starter Quota","id":"g1-plus-tier"}}}}
```

Without a sign in, `session/new` answers `{"code":-32000,"message":"Authentication required"}`.

## Models

`agy models` prints the same list as `availableModels`, one `id<TAB>name` per line after a
`Fetching available models...` line, and exits 0. Signed out it prints "Please sign in to view
available models" and exits 1. Unified Dev reads its list from `agy models`, because opening a
session to read it would add an empty conversation to the owner's history on every refresh. The
first line is the model `session/new` reports as `currentModelId`, so it is the default.

The ids fold the thinking level into the model: `gemini-3.8-flash-low` is Gemini 3.8 Flash at
`thought_level` low. `session/set_config_option` with `configId: "model"` takes either form: a
folded id sets the model and the level together, and choosing a model with no levels removes the
`thought_level` option from the reply. So Unified Dev offers the folded ids as models and announces
no separate effort.

`value` is a plain string. Grok takes `{"value": "<id>"}`; Antigravity answers that with `-32602`
"cannot unmarshal object into Go struct field .value of type string". `session/set_mode` and
`session/set_model` exist as well and answer `{}`; a mode change also arrives as
`current_mode_update`.

## Modes

`default` asks before edits and commands, `accept-edits` approves file edits in the workspace,
`auto` approves edits and safe commands and asks before irreversible ones, `plan` plans before
acting. Unified Dev sets the mode with `set_config_option` `mode`, mapping its own permission modes
onto these four, and launches with `--dangerously-skip-permissions` for bypass.

## A turn

`session/prompt` is held open until the turn ends, as for Grok. Updates arrive as `session/update`:

- `user_message_chunk`: the prompt echoed back (ignored)
- `session_info_update`: a generated `title` (ignored)
- `agent_message_chunk`
- `tool_call` / `tool_call_update`
- `usage_update`: `used` and `size` of the context window
- `config_option_update`, `current_mode_update`, `available_commands_update` (ignored)

No `agent_thought_chunk` arrived in any turn measured, at either thinking level.

The reply to `session/prompt` carries the turn's usage, which Grok's does not:

```json
{"stopReason":"end_turn","usage":{"inputTokens":9193,"outputTokens":1,"cachedReadTokens":0,
 "cachedWriteTokens":0,"thoughtTokens":0,"totalTokens":9194}}
```

A tool call names its tool in `name` (Grok uses `toolName`) and repeats its input in `args` and
`rawInput`, with capitalised keys:

| `name` | `kind` | input keys | asks first |
| --- | --- | --- | --- |
| `run_command` | `execute` | `CommandLine`, `WaitMsBeforeAsync`, `toolSummary` | yes |
| `read_file` | `read` | `Path` | no |
| `write_file` | `edit` | `Path`, `Content` | yes |
| `edit_file` | `edit` | `Path`, `Target`, `Replacement` | yes |
| `mcp_<server>_<tool>` | `other` | the tool's own arguments, plus `toolSummary` | yes |

A tool call is announced `in_progress`, moved to `pending` while it waits for an answer, back to
`in_progress`, then `completed` or `failed`. `run_command` finishes with `rawOutput:
{"output": "...", "exit_code": 0}` and the same text in `content`.

## Permissions

`session/request_permission` is a server-to-client request whose id is a **string** (`"1"`). The
payload is the pending tool call and two options:

```json
"options":[{"optionId":"allow","name":"Allow","kind":"allow_once"},
           {"optionId":"deny","name":"Deny","kind":"reject_once"}]
```

There is no `allow_always`, so Unified Dev offers no "always" from the agent and keeps its own
grants. An edit's request carries a `diff` content item with `path`, `oldText` and `newText`.
Answering `deny` marks the tool call `failed` and the turn ends with `end_turn` and no message.

## Cancelling

`session/cancel` is a notification. The pending `session/prompt` then answers
`{"stopReason":"cancelled", "usage": {...}}` within a second.

## Resuming

`session/resume` with the stored `sessionId`, `cwd` and `mcpServers`, in a fresh process, answers
with the same shape as `session/new` and a `session_info_update` carrying the old title. The next
prompt saw the earlier turns: asked what an earlier command printed, it answered correctly.
`session/close` answers `{}`.

## MCP

`mcpServers` on `session/new` or `session/resume` registers a stdio server, with `env` as an
array of `{name, value}` objects, the same shape Grok takes. A server registered as `probe-bridge`
offering `ping` was called as `mcp_probe-bridge_ping`, saw the environment it was given, and asked
permission first. Unified Dev reads that name as `mcp__<server>__<tool>`, splitting at the first
underscore after the prefix, which holds while the server name has none; the bridge's is
`unifieddev-workspace-bridge`.

## Accounts, quotas and spend

The login follows `HOME`: under a fresh `HOME`, `session/new` answers "Authentication required" and
the CLI writes `.gemini/config` and `.gemini/antigravity-cli` there, so the login is not in a
keychain shared across homes. Unified Dev runs the default account only, and does not read
anything under `~/.gemini`. Accounts per profile need a variable that moves less than the whole of
`HOME`; `--app-data-dir` refuses an absolute path, and none was found.

The session reports a tier name, `_meta.antigravity.tier.name`, and nothing about what is left of
it. No quota request was found. Usage per turn is the `session/prompt` reply above.

## Signing in

`agy acp --login` is documented as "Log in with Google interactively, then exit". It was not run,
because the owner's account was already signed in. Running `agy` with no arguments signs in on
first use, which is how the owner did it.
