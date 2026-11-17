# The Claude Code stream-json protocol

Ground truth, captured from `claude` on this machine on 2026-08-18. A real capture lives at
`Tests/fixtures/session-basic.jsonl` (55 lines: thinking, two tool calls, two tool results, text,
result). Hook payloads in that file were trimmed because they were enormous, nothing else was
touched.

## How Unified Dev invokes it

```
claude
  -p
  --output-format stream-json
  --input-format stream-json
  --include-partial-messages
  --verbose
  --permission-mode <auto|acceptEdits|bypassPermissions|plan>
  --permission-prompt-tool stdio
  --model <opus|sonnet|haiku|...>
  [--effort <level>]                 only when the session has one
  [--thinking disabled]              fast mode, and only when it is on
  [--settings '{…}']                 an output style when one was chosen, and for a workspace chat
                                     in acceptEdits, `ask` rules for the bridge tools that
                                     can name another profile (see docs/BRIDGE.md)
  [--mcp-config <path>]              the workspace bridge, a file and never inline JSON
  [--resume <agent session id>]
```

`--verbose` is required with `-p --output-format stream-json`, otherwise the CLI refuses to run.

`--permission-prompt-tool stdio` is undocumented, absent from `--help`, present in the binary, and
always on. Without it the CLI answers permission questions on the user's behalf and the answer is
no, which was every `permission-rule` refusal not made by a hook. It does not make the CLI ask
more: the classifier still approves what it approved before, measured at zero questions over seven
tool calls in one ordinary turn. The paragraph above `AgentRunner.argv` is where that measurement
lives, along with why `--settings` takes one object rather than accumulating and why the bridge is
handed over as a file (argv is visible in `ps`, and an agent runs `ps`).

Working directory is the worktree. Input is NDJSON on stdin, output NDJSON on stdout. stdin stays
open for the whole session so follow-up turns are just more lines.

### Sending a turn

One JSON object, one line:

```json
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"do the thing"}]}}
```

### Sending into a turn that is already running

Measured on `claude 2.1.260` on 4 September 2026, driving the invocation above with a cheap model.
A second user line was written to stdin four seconds into a running turn. It was **accepted**: no
error, nothing lost, and the CLI did not close the pipe.

What it did with it depends on what the turn had left to do. The probe's turn was prose with no
tool call after the injection, and the CLI finished it, emitted its `result`, then emitted a
**second `init`** and ran the injected line as a turn of its own. The other landing is in the CLI's
own copy: a message whose origin is the person is framed as "The user sent a new message while you
were working", with a paragraph under it saying that is how Claude Code surfaces a mid-turn
message, within the running turn and often alongside the next tool result rather than as a separate
turn. So a turn with a tool boundary left in it takes the message inside the turn, and a turn
without one runs it next.

Both are landings Unified Dev already handles. `AgentRunner.ingest` applies `turnStarted` on an `init`,
which is the fix written for the CLI's habit of starting turns of its own (see `StrayResult`), so a
second `init` puts the chat back to running rather than leaving it drawn as idle through a turn.

`AgentKind.acceptsMidTurnMessage` is where this is written down as a fact the app reads, and
`DeliveryHold.allowsDelivery(on:)` is what it decides.

## Output events

Every line has `type`. Every line except a few carries `uuid` and `session_id`.

### `system` / `init`

First line of the session. Carries the fields Unified Dev needs to bind a session:

```json
{"type":"system","subtype":"init","session_id":"f93932c9-...","cwd":"/path",
 "model":"claude-sonnet-5","permissionMode":"bypassPermissions",
 "tools":["Bash","Read",...],"slash_commands":[...],"agents":[...],
 "output_style":"default","uuid":"..."}
```

`session_id` is what `--resume` takes later. Persist it the moment this arrives.

`--resume` looks for the transcript under `projects/` in the config directory the process starts
with, and nowhere else. Measured on `claude 2.1.309` on 29 October 2026, in a throwaway config
directory with no sign-in: with the transcript copied under `projects/` the session loads and the
turn runs, and with it missing the CLI prints `No conversation found with session ID: <id>` and
ends with `is_error: true`, `subtype: error_during_execution` and zero cost. The lookup happens
before authentication is checked, so a session started under one account cannot be resumed under
another, whichever of the two is signed in. `AgentSessionSettlement` is the decision: a stored id is
never cleared by a change of account. When the account recorded on the session is known and differs
from the one about to run, or when the owner deliberately moves a chat with no recorded account,
`Store.switchSegment` parks the id on the segment it belongs to and the chat continues on another
segment, which gets the id back if the chat returns to that account. A session with no recorded
account is otherwise left as it is, because nothing says where its transcript lives.

A `--resume` that finds no transcript ends the process at once: measured on `claude 2.1.309` on
29 October 2026, for an id that does not exist anywhere and for one that exists under another
config directory, no `system/init` arrives. The output is the plain line `No conversation found with session ID: <id>`,
then one `result` with `subtype: error_during_execution` whose `session_id` is the id that was asked
for, and exit status 1. `SegmentResume.refused` reads that shape, and only before the first `init` of
a process the owner has not stopped. The runner clears the stored id and sets the segment's cursor
to -1: the turn that was refused stays failed, and the next send opens a new session carrying the
whole conversation. An `init` naming another id than the one asked for
(`SegmentResume.lostHistory`) resets the cursor the same way, and nothing that turn replies moves it
again, because the prompt already sent carried no delta. Only the first `init` of a process is read
like this; a brand new session getting its first id is not a loss.

The same design is applied to Codex and Grok, whose threads also live under the directory the
account gives them (`CODEX_HOME`, `GROK_HOME`). All three variables are measured to move the home
and to carry the login with it (`docs/AGENTS-INTEGRATION.md`), but resume itself was measured only
for Claude Code. Nothing here says what `thread/resume` does in another Codex home or what Grok's
resume does in another Grok home.
Both runners treat any failed resume alike: they open a new thread or session, and only once that
has worked do they reset the cursor and replace the stored id. A server that is down therefore
changes nothing, and a resume that was really refused has the whole conversation in that same send.

`model` is an alias resolved, or the string `--model` was given when it names no alias. Measured on
`claude 2.1.309`, `--model opus` reports `claude-opus-5-5`, and the same alias reported
`claude-opus-5` on `claude 2.1.261`, so what an alias means belongs to the CLI and its account.
`ClaudeResolvedModel` keeps the last answer per alias and account. A `--model` nobody has ever heard
of comes back in this field unchanged, so this line never promises that the model exists.

### What an alias resolves to, without a turn

`init` is written before the first request to the model leaves, so the CLI can be asked what an
alias means without a turn. `ClaudeAliasProbe` starts
`claude -p . --model <alias> --output-format stream-json --verbose` for each alias in turn, under the
account's own directory and login, takes the `model` of the first `init`, ends the process and waits
for it to exit. A process that ignores `SIGTERM` for two seconds is sent `SIGKILL`.

Two local sockets stand in for the network. `ANTHROPIC_BASE_URL` points at an
`UnansweredEndpoint`, a socket on 127.0.0.1 that listens and never accepts, so the request to the
model sits in the kernel's queue unread. `HTTP_PROXY`, `HTTPS_PROXY` and `ALL_PROXY`, in both cases,
point at a `RefusingEndpoint`, which accepts and resets every connection at once. `NO_PROXY` names
the loopback, so only the model request goes to the first socket and everything else the CLI sends
goes to the second.

The proxy is not there for tidiness. Measured on `claude 2.1.322` on 10 November 2026, in an
isolated `CLAUDE_CONFIG_DIR` with made up credentials, a start with no proxy opened a connection to
Anthropic before `init` was written: to `api.anthropic.com` with a token that had not expired, and
to `platform.claude.com` to refresh one that had. With a real expired login that request carries the
real refresh token, and an answer to it rewrites the account's credentials. With the proxy pointing at
a socket that never accepts, nothing left the
machine but the refresh held `.oauth_refresh.lock` in the account's directory, and the next start
waited 7.7 seconds before it would refresh. With a socket that resets, `init` arrived in 0.26 seconds,
no connection left the machine, no lock was left behind and the next start refreshed at once.

`--setting-sources local` means neither the account's `settings.json` nor a project's shared one is
read, so nothing in them can send the request elsewhere: measured, an account `settings.json` naming
its own base URL,
Bedrock, an `HTTPS_PROXY` and an `apiKeyHelper` still sent the request to the local socket, and the
helper never ran. The login is not a settings file and is still used. `--settings` puts back what the
probe needs: both addresses, Bedrock, Vertex and Foundry switched off, `NO_PROXY`, `disableAllHooks`
and `autoMemoryEnabled: false`. The same variables go into the environment, replacing any inherited
proxy. `local` still reads `<cwd>/.claude/settings.local.json`, so each probe runs in a directory of
its own made with `mkdtemp` and removed when the last process has exited, never in the shared
scratch directory. With `--strict-mcp-config`, `--no-session-persistence` and
`--disable-slash-commands` nothing of anyone's runs.

Managed settings outrank every flag, so the probe does not start at all when one of them sets
anything: `/Library/Application Support/ClaudeCode/managed-settings.json`, any `*.json` in its
`managed-settings.d`, the `com.anthropic.claudecode` profile under `/Library/Managed Preferences`
for this user or for the machine, or a `remote-settings.json` in the directory the CLI will use, which
is where it keeps what the organisation's server sent it. That directory is the one the launch names in
`CLAUDE_CONFIG_DIR`, including one the app inherited, and `~/.claude` only when nothing names one.
An empty object, which is what a personal account's `remote-settings.json` holds, does not count; a
file that cannot be read, or a `managed-settings.d` that cannot be listed, does. Those paths are the ones `claude 2.1.322` names; writing to `/Library` needs root, so the precedence
itself was not reproduced here.

An alias the account pins with `ANTHROPIC_DEFAULT_<ALIAS>_MODEL` in the `env` of its own
`settings.json` is not asked: the probe reads that value from the file, since a turn would run it,
and records it in place of an answer. The file is parsed as JSON and nothing else in it is used. A pin
the picker cannot read a version of that alias from, such as a provider's own model id, an id of
another family or an older naming, is recorded as it is, and the picker names no version for that
alias rather than one it cannot vouch for.

Each start writes the account's `~/.claude.json`. The CLI takes its own lock and writes through a
temporary file, and twelve probes started at once in one directory left a file that parsed and no
temporary file behind. Inside the app, the probe is also kept apart from every other start of the
CLI under the same account: `ClaudeAccountActivity` holds an account while an `AgentRunner` process
runs, while the usage question of `ClaudeCodeQuotaSource` runs, while `AgentAccountLiveness` asks
`claude auth status`, and while `WorkspaceNamer` names a workspace, in each case until the process
has exited or been killed. A probe does not start a launch while the account is held, and a start that
arrives during a launch waits for it to end, after which the probe asks nothing more. A stop pressed
during that wait ends the turn at once, without waiting for the probe, and so does cancelling the task
that waits. A process that a failed send started and never wrote a turn to is kept, because a delivery retried
a moment later uses it, but idle eviction ends it even though it has no agent session id yet: with no
turn there is nothing to resume, and ending it is what gives the account back.

What the app cannot hold is a start it does not make: a `claude` typed into one of the app's
terminals, a second copy of the app, or the CLI started anywhere else on this Mac. Those can run
while the probe does, and two processes can then write `.claude.json` and wait on the account's
OAuth refresh lock at the same time. The CLI's own lock and its writes through a temporary file are
what keep that file whole in that case, not the app.

Measured on `claude 2.1.309`, the four built in aliases answered `claude-fable-5-1`, `claude-opus-5-5`,
`claude-sonnet-5-5` and `claude-haiku-5-5`, under a second for all four. On `claude 2.1.322` the same
probe answered `claude-fable-5-2` for `fable`, so what an alias names moves with the installed CLI
and not with the account. `ClaudeAliasRefresh` therefore probes each account once per version of the
CLI: it reads `claude --version` when the catalogue is configured and whenever the composer loads its
models, at most once a minute per account, and probes again when the version differs from the one
that last answered, or when the managed settings or the account's pins have changed since. A version it
cannot read keeps the last answer. An account with a turn running is
left for the next check. A probe that missed any alias is tried again after ten minutes rather than
every minute, because each attempt starts the CLI up to four times, and what it did answer is kept.

The probe and a turn write the same setting per alias and account, and a turn writes beside it the
version of the CLI that ran it, from `claude_code_version` in its `init`, or `unversioned` when the
`init` names none. A probe of that same version leaves the turn's answer alone, because a turn also
sees what the probe cannot, such as a pin in the project's own settings, and so does a probe whose CLI
version could not be read, and any probe after a turn that named no version. A probe of another
version replaces it, and a pin read from the account's
settings replaces anything. Each write is one transaction: a turn writes the model and its version
together, and a probe reads the turn's version and writes its answer in the same step, so a turn
recorded while a probe is being recorded can never end up with the probe's model under its version. The model picker names the version of what is stored, and only with
nothing stored falls back to the newest usable entry of the account's `additionalModelOptionsCache`.
The list comes last because it lags: it is what the server offered when the CLI last wrote the file,
and it has been seen naming an older version than the alias runs. The picker is per account, so a pin
in one project's settings is shown once a turn has run there, and is shown for the account's other
projects too until another turn or a new version of the CLI replaces it.

### Which models it has, and what happens when it does not have one

There is nothing to ask, and a file to read instead. Measured on `claude 2.1.278` on 24 September
2026, none of it spending a turn.

No subcommand lists models: `agents`, `attach`, `auth`, `auto-mode`, `doctor`, `gateway`, `import`,
`install`, `logs`, `mcp`, `plugin`, `project`, `respawn`, `rm`, `setup-token`, `stop`,
`ultrareview`, `update`, and nothing else. Under `--input-format stream-json` the `init` line does
not arrive until the first user message is written to stdin either: a session started and left
alone printed seven `hook_started` and seven `hook_response` lines and then waited, with no `init`
and no `model` anywhere. Asking with a prompt and nowhere to send it does answer, alias by alias,
which is what the section above does; for the list of models there is still only the file.

**`~/.claude.json` carries the answer.** The CLI rewrites it on startup with what the server told
it, and `additionalModelOptionsCache` is the list its own `/model` picker is built from. It is the
same file `AgentCatalog.claudeAccountPath` already reads for the account, so this costs one more
read of a file the app opens anyway. As measured:

```json
"additionalModelOptionsCache": [
  {"value": "claude-fable-5-1[1m]", "label": "Fable",
   "description": "Fable 5.1 · Most capable for your hardest and longest-running tasks"},
  {"value": "cc-update-required-1", "label": "Opus 5.5 (disabled)",
   "description": "Update to 2.1.280+ to use Opus 5.5", "disabled": true}
]
```

Three things that shape `ClaudeModelOptions`. The list is **additional** options, so the four
aliases every install takes are not in it and stay in `ClaudeModelCatalog.builtIn`. A `value` is
not always a model id: `cc-update-required-1` is a placeholder for one this install cannot reach,
which is why the name comes from `label` when `ClaudeModelRank` does not recognise the id, and from
`ModelLabel` when it does, because `label` reads "Fable" for a model we would rather call
"Fable 5.1 (1m)". And `disabled` comes with its reason in `description`, which is worth showing
rather than hiding: on this machine it is the whole answer to why Opus 5.5 cannot be chosen.

`modelAccessCache` and `orgModelDefaultCache` sit beside it and were empty on the account measured,
so nothing is read from them yet.

`ClaudeModelSource` puts that read behind the same `AgentModelCache` Codex and Grok use, and joins
`AgentModelSource.live`, so a model that arrives after this build ships shows up on its own.

Nothing is checked at startup. A model that does not exist is refused only once a turn is sent, and
the refusal arrives in four places at once:

```
stderr:  [claude-code:unrecognized_model] {"model":"definitely-not-a-model","query_source":"sdk"}
exit:    1
result:  "is_error":true, "subtype":"success", "terminal_reason":"api_error", "total_cost_usd":0,
         "result":"There's an issue with the selected model (definitely-not-a-model). It may not
                   exist or you may not have access to it. Run --model to pick a different model."
```

`terminal_reason: api_error` is a bucket shared by every failure that happens at the API: a refused
model and a signed-out account both arrive under it, so it is only the anchor and the words decide.
A signed-out account was measured on `claude 2.1.309` on 29 October 2026 as `subtype: success`,
`is_error: true`, `num_turns: 1`, `terminal_reason: api_error` and `result: "Not logged in · Please
run /login"`, after an assistant message from model `<synthetic>` carrying `error:
authentication_failed`. `AgentAccountSignOut.measuredWords` and `measuredTerminalReason` are those
two fields.

The `subtype` stays `success`, so `is_error` is the only field in the `result` that marks it. The
name of the refused model is in the stderr line as JSON and in the `result` sentence as English, so
`ModelRefusal` reads the first and never the second. Note the shape of the failure: a `result`
**does** arrive, which is why `UnfinishedRun.of` has to let this one case past its `sawResult`
guard, or the exit that carries the marker is discarded and the turn fails saying nothing useful.

### `assistant`

**The important one.** Emitted once per content block, already split, with the block complete.
A transcript can be built from these alone: the `stream_event` deltas below are only needed to
show text arriving live.

```json
{"type":"assistant","uuid":"...","parent_tool_use_id":null,"session_id":"...",
 "message":{"id":"msg_011...","role":"assistant","model":"claude-sonnet-5",
   "stop_reason":null,
   "usage":{"input_tokens":2,"cache_creation_input_tokens":13435,
            "cache_read_input_tokens":24424,"output_tokens":2,
            "cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":13435},
            "service_tier":"standard"},
   "content":[ <exactly one block> ]}}
```

`content[0]` is one of:

| block | fields |
|---|---|
| `text` | `text` |
| `thinking` | `thinking`, `signature` |
| `tool_use` | `id` (`toolu_...`), `name`, `input` (arbitrary JSON object) |

`parent_tool_use_id` is non-null when the event comes from inside a subagent (the Agent tool).
Nest or indent those rows rather than mixing them into the main flow.

Several consecutive `assistant` events can share one `message.id`. That is one assistant turn
split across blocks, not several turns.

### `user`

A tool result being fed back. Not something a human typed.

```json
{"type":"user","uuid":"...","parent_tool_use_id":null,"session_id":"...",
 "message":{"role":"user","content":[
   {"type":"tool_result","tool_use_id":"toolu_01PpK...","content":"1\thello\n2\t",
    "is_error":null}]},
 "toolUseResult":null}
```

`content` is either a string or an array of blocks (`{"type":"text","text":...}`, and image
blocks for screenshots). `is_error` is `true` when the tool failed. Match `tool_use_id` back to
the `tool_use` block to render the pair as one row.

A call that never ran carries `tool_result_meta` on the same line, naming why:

```json
"tool_result_meta":[{"id":"toolu_01Xe8...","non_execution_kind":"permission-rule",
  "permission_decision":{"decision":"reject","source":"hook","reason_type":"hook"}}]
```

`non_execution_kind` is `permission-rule` for a `PreToolUse` hook too, so it cannot tell a hook from
a permission rule. `permission_decision` can: `decision` of `reject` with `source` of `hook` means
no permission mode would have let the call through, and `ToolRefusal.hookRefused` is that case. A
hook can also accept a call that is then interrupted, which is not a refusal of its. Measured on `claude 2.1.309`. The
message text is the hook's own and decides nothing. `permission_denials` on the `result` line lists
both, with only `tool_name`, `tool_use_id` and `tool_input`, so a turn's real denials are the ones
whose `tool_use_id` no hook refused.

### `stream_event`

Raw passthrough of the Anthropic streaming API, only present with `--include-partial-messages`.
Use for live typing, then reconcile against the `assistant` event that follows.

```json
{"type":"stream_event","event":{...},"session_id":"...","uuid":"...","parent_tool_use_id":null}
```

`event.type` is one of `message_start`, `content_block_start`, `content_block_delta`,
`content_block_stop`, `message_delta`, `message_stop`.

`content_block_start` carries `index` and `content_block` (`{"type":"text"|"thinking"|"tool_use",...}`).
`content_block_delta` carries `index` and `delta`, whose `type` is:

- `text_delta` with `text`
- `thinking_delta` with `thinking`
- `input_json_delta` with `partial_json` (accumulate the string, it parses only once complete)
- `signature_delta` with `signature`

### `system` (other subtypes)

- `status` with `status: "requesting"` and similar. Drives a "thinking" indicator.
- `thinking_tokens` with `estimated_tokens` and `estimated_tokens_delta`. Live thinking counter.
- `hook_started` / `hook_response` with `hook_name`, `hook_event`, `output`, `stdout`, `stderr`,
  `exit_code`, `outcome`. Payloads can be hundreds of kilobytes. Never render them raw.
- Unknown subtypes will appear over time. Ignore them without failing.

### `result`

Last line of a turn.

```json
{"type":"result","subtype":"success","is_error":false,
 "duration_ms":7880,"duration_api_ms":7851,"num_turns":3,
 "stop_reason":"end_turn","session_id":"...","total_cost_usd":0.119,
 "result":"Created out.txt with \"BATON\".",
 "usage":{"input_tokens":6,"output_tokens":360,
          "cache_read_input_tokens":100420,"cache_creation_input_tokens":13928,
          "output_tokens_details":{"thinking_tokens":150}},
 "modelUsage":{"claude-sonnet-5":{"contextWindow":1000000,"costUSD":0.119,...}},
 "permission_denials":[],"terminal_reason":"completed","uuid":"..."}
```

`subtype` is `success`, or `error_max_turns` / `error_during_execution` on failure.
`modelUsage.<model>.contextWindow` is where the context-window size comes from, so a
"how full is the context" gauge can be drawn.

**It is the last line of a turn, and not always of the turn you sent.** The CLI starts turns of
its own, and when it does the result carries an `origin` object naming why:

```json
{"type":"result","subtype":"success","is_error":false,"duration_ms":60,
 "duration_api_ms":0,"num_turns":0,"result":"","origin":{"kind":"task-notification"},...}
```

Measured on 25 August 2026, twice, in two workspaces. Both times a `--resume` brought back a
session that had a background task notification waiting for it, and the CLI ran that as a turn
before it read anything from stdin: `init`, this line, then a second `init` for the turn the user
had actually sent. A result answering a prompt names no origin at all. See `StrayResult`, which is
the bug that cost.

The same thing happens mid process, and there the turn does real work. Measured on `claude
2.1.268` on 11 September 2026: a turn put `sleep 5` in the background and ended; five seconds later
the CLI wrote `task_updated`, then `system/task_notification` for the command, then a second `init`,
then a whole turn, closed by a `result` with `origin: task-notification`. The notification is the
only line saying why that turn began, and its `summary` reads `Background command "<description>"
completed (exit code 0)`. Unified Dev stores it when it arrives between turns and draws it as the turn's
opening line. See `BackgroundWake`.

### A turn stopped by the usage limit

The stop is an `assistant` line, not a `result` and not a `system` line. It has model `<synthetic>`,
zero usage, one `text` block and, beside `message`, the error fields. They have two spellings, and the
one that reaches Unified Dev is the stream's:

```json
{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","stop_reason":"stop_sequence",
 "content":[{"type":"text","text":"You've hit your session limit · resets 7:10am (Europe/Luxembourg)"}]},
 "error":"rate_limit","is_api_error_message":true,"api_error_status":429}
```

Claude Code's own transcript files (`~/.claude/projects`, versions 2.1.219 to 2.1.237) hold the same
line as `isApiErrorMessage` and `apiErrorStatus`, and some versions add `quotaLimits` there. The stream
has no `quotaLimits`: `claude 2.1.309` writes `api_error: usage_limit_reached` and
`api_error_params.rate_limit_info` instead, and leaves out `api_error_status` on an error that has no
status. Nothing stored in `messages` comes from those files, so `TurnStopCause` reads the stream's names
alone.

Not every part of this was captured. `Tests/fixtures/claude-turn-died-mid-response.ndjson` is a real
stream capture of another API error, which proves the spelling and the shape, and the binary proves the
fields of a limit. No real line carrying `api_error` has been seen, on the stream or on disk: that reading rests on the
binary alone. The words of a limit line come from the transcript files, where they name the window
that ran out (`session` in every sample); the `resets` clause is local time and carries no date. The
`result` line that follows a limit on the stream is inferred from that capture, which closes with
`subtype: success` and `is_error: true`.

`AgentEvent.decode` turns the line into `.assistantText`, so it is stored as an `assistantText` row with
the whole line as its payload. `TurnStopCause` reads that row. It needs model `<synthetic>` and `error:
rate_limit`, and then `api_error` decides: `usage_limit_reached` is the limit, whatever the words say, and
any other value is not, whatever the words say. The binary documents this as the field to key on, and
says the other refusals that share `error: rate_limit` never carry that value. A line with no `api_error`,
from an older CLI, needs `is_api_error_message: true`, status 429 and text starting `You've hit your` and
containing `limit`. Only the last turn counts (rows after the last row that
opens a turn, `MessageKind.opensTurn`), and the limit row must be the last output in it.
`ConversationHandoff` counts that turn as unfinished whatever `result` follows it, because a limit
outranks a clean `result`.

### `rate_limit_event`

One per turn, and it carries **one window**, never a set:

```json
{"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1787508600,
 "rateLimitType":"five_hour","overageStatus":"rejected",
 "overageDisabledReason":"org_level_disabled","isUsingOverage":false},"uuid":"...","session_id":"..."}
```

Measured on 23 August 2026 against the installed binary, and recorded with a second payload from a
busier account in `Tests/fixtures/rate-limits.jsonl`. Three facts, all of which shaped `AgentQuota`:

1. `rateLimitType` names a single window. `five_hour` and `seven_day` are the values observed, there
   is no array, and there is no way to ask for the rest, so what Unified Dev knows about an account
   accumulates over turns.
2. **`utilization` is absent below a warning threshold.** The payload above has no usage figure at
   all. The one that does carries `"status":"allowed_warning"` and `"surpassedThreshold":0.75`
   beside it, so the number arrives only once the account is near the wall. Store that as unknown,
   never as zero: an empty bar is a claim, and it is a claim this protocol never made.
3. **There is no monthly window.** Unified Dev shows the two it is given and says nothing about a third.

Surface it quietly, never as an error. `AgentQuotaAdapters` is the reader.

### `control_request` / `control_response`

Not an event, a question. With `--permission-prompt-tool stdio` the CLI asks before running a tool
it is not allowed to run outright, and holds the turn open until an answer arrives on stdin.

```json
{"type":"control_request","request_id":"…",
 "request":{"subtype":"can_use_tool","tool_name":"Bash","input":{…},
            "permission_suggestions":[…]}}
```

Only `can_use_tool` is lifted out. The other control subtypes are the CLI answering Unified Dev, or
asking something Unified Dev has no business answering, and they stay raw rather than half understood.
`request` also carries `display_name`, `tool_use_id`, `description`, `decision_reason`,
`decision_reason_type`, `blocked_path`, `suppress_always_allow_rule`, `requires_user_interaction`
and `classifier_approvable`, all optional. **`decision_reason` may carry ANSI escapes**, which the
CLI's own schema says in as many words, so it is stripped before anything renders it.

The answer is one line back:

```json
{"type":"control_response","response":{"request_id":"…","subtype":"success",
 "response":{"behavior":"allow"|"deny",…}}}
```

An allow carries `updatedInput`, which is the input that was asked about and unedited unless the
tool asked a question the user typed an answer to. A wider scope than once carries
`updatedPermissions`, which is the CLI's own suggestion aimed at the session. A deny carries
`message` and `interrupt`. The `request_id` has to match the pending ask or the answer does
nothing: the CLI refuses a response whose tool disagrees with the question and logs the mismatch.
`PermissionAsk` reads these and `PermissionAnswer` writes them.

This wire used to fall through to `unknown` and be dropped on the floor, which is exactly what
"Unified Dev never asks" looked like from the inside: the CLI was willing to ask and nobody was reading
the line. A decoder that took the event list above as complete would hang the turn the same way.

## Rules for the decoder

1. **Never fail the stream on an unknown event.** New `type` and `subtype` values ship
   regularly. Decode what is recognised, keep the raw JSON for everything else, carry on.
2. **Keep the raw line.** Unified Dev stores the original JSON for every row so a renderer added later
   can show detail that was not decoded at the time.
3. Lines can be very large (a hook response, a big tool result). No length assumptions.
4. A malformed line is possible if the CLI crashes mid-write. Skip it, do not abort.
