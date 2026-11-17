# Chat segments

A chat can change agent without ceasing to be the same chat. The composer's model picker moves it
from Claude Code to Codex or Grok, the transcript stays, a divider marks the place, and the agent
that comes in is told what it missed. This document describes how that works and what it
assumes.

## Segments

A **chat** is a row of `sessions`, the thing the app shows. A **segment** is one stretch of it run
by one native session: one agent, one account, one `agent_session_id`. A chat has one segment or
more, and exactly one is active. The `sessions` columns `agent_kind`, `account_id`,
`agent_session_id`, `model`, `effort` and the four counters describe the active segment, so the
rest of the app reads a chat the way it always did.

`session_segments` holds the rest. A segment records:

| Column | Meaning |
| --- | --- |
| `agent_kind`, `account_id`, `agent_session_id` | who ran it, under which account, and the id its CLI stores the conversation under |
| `model`, `effort` | what it was last asked to run; an empty `effort` means nothing was asked, and the CLI runs its own |
| `cursor_seq` | the `seq` of the last `messages` row this native session knows, `-1` when it knows none |
| `entered_seq` | the `seq` of the divider that made it active, `0` for the first segment |
| `is_active` | one per chat, held by a partial unique index |
| `input_tokens`, `output_tokens`, `cost_usd`, `context_tokens` | the counters of that segment, so the `sessions` counters always describe the active one |
| `source_received_seq` | the `seq` of the owner's message whose turn delivered the chat's source to this segment, NULL until then, see Opening in a new chat |
| `delta_prompt_seq`, `cursor_before_delta_seq` | the record of the last delta, see below |

A chat that existed before segments gets its first segment from its own columns, in the migration
and again lazily when the first switch finds none. Every new session is given one when it is
created. `account_id` follows the rule of `sessions.account_id`: forgetting an account sets it to
NULL. `forgetAgentAccount` also clears the stored session id and sets the cursor to `-1` on every
segment that account held and, because `update(sessionID:accountID:)` records an account on the chat
without touching its segment, on the active segment of every chat whose `sessions.account_id` is that
account, together with `sessions.agent_session_id`. That history is no longer reachable, so the next
send carries the whole conversation.

Because that history now goes to whichever account the chat resolves to, possibly of another
organisation, `forgetAgentAccount` also writes a setting `chat.lostAccount.<session id>` for every chat
whose `sessions.account_id` was the account forgotten. `Store.runnerSeat` reads it as
`RunnerSeat.lostItsAccount`, and `AgentSessionSettlement.decide` turns the next send of such a chat
into a segment switch rather than a silent record, with a notice that says the account was removed and
names the one the history went to. `switchSegment` removes the setting, and so does closing the chat. A
chat that goes with its workspace or project takes no setting with it, so each forget also removes the
marks of chats that no longer exist.

The full transcript is `messages`, by `session_id` and `seq`. Nothing about a segment duplicates
it, which is why the delta is computed from the database and never from a CLI's files.

## Changing segment

`Store.switchSegment(sessionID:to:)` is one transaction in the Store actor: it parks the active
segment with the chat's current values, finds or creates the segment for the target, copies that
segment's values onto the chat, writes the divider row and marks the segment active with
`entered_seq` set to the divider's `seq`. A target equal to the current agent and account changes
nothing.

A segment that was parked with a session id is entered again when the chat returns to the same
agent and account, so the CLI resumes its own conversation. Any other target gets a new segment
with no session id and cursor `-1`.

Three callers reach `switchSegment`:

- `AgentSwitch.retireAndSwitch`, for the provider picker on a chat that has spoken
  (`BackendChange.switchInPlace`) and for an account change on the same provider from the quota
  offer in the menu bar panel;
- `AgentSessionRecord.write`, when `AgentSessionSettlement.decide` finds at send time that the
  account recorded on the chat is not the one it now resolves to, or that the account it ran under was
  removed. The chat moves and a notice names
  the account (`AgentSessionSettlement.notice`), because the history is going to another account,
  possibly of another organisation;
- the preview scenario seeder, for a `handoff` line.

The divider is a `HandoffMark.continued`, which records the agent, the model, the agent left and the
name of the account entered, as `AgentAccountNames.spoken` gives it when the switch is made. It reads
"Continued with Codex · gpt-5.6-sol" when the provider changes, and "Continued with Claude Code under
ada@client.example · opus" when the switch is between accounts of the same provider, so two accounts of
one provider can be told apart in the history. A divider stored before the name was recorded has none,
and reads as it always did.

A model change inside the same provider and account is not a segment, and stays on the session
editor.

A chat that has not spoken yet changes provider in place, with no divider. A chat whose agent
runs in a terminal (`usesInteractiveTerminal`) cannot take invisible text, so a provider change
there opens a new chat instead, with a notice saying why.

### The steps around it

`AgentSwitch.steps(for:)` orders what the transcript model does, and one driver,
`carryOutAgentSwitch`, carries out both the provider and the account path. A move found at send time
takes none of these steps: the transcript model retires the runner and calls `AgentSessionRecord.write`
while it builds the next one.

1. Stop the running turn, if there is one. The draft and the queue are not touched.
2. Deny open permission asks and questions as stopped.
3. Retire the runner: terminate it, detach it, and hold any new runner build until it has exited.
4. Switch the segment, write the chat's permission and interaction modes, then settle the queue.
   The switch and the settlement are one transaction each and the modes are a write between them.
   When the switch fails the chat has not moved and an error notice says so. When the queue
   settlement fails the chat has already moved, the queued messages
   are left waiting unchanged, an error notice says so (`AgentSwitch.queueFailure`), and the queue
   does not drain.
5. End subagents, wait for the old runner to stop writing, close the turn.
6. Queue the resume when it applies, then drain the queue.

`AgentSwitch.refusal` declines the switch while the workspace is archiving, while a rewind is
unresolved, while a turn's file changes are being saved, while the transcript is catching up with
its agent, and while another switch is still shutting its runner down.

A runner is created for one segment, and its `save` writes the chat's columns only while that
segment is active. `Store.update(sessionID:fromSegment:)` refuses the write of a runner whose segment
has been parked, and a send on that runner stops it with `ProviderIdleError.retired`. A late `save`
from the old agent therefore cannot overwrite the new agent's session id. Its rows are a different
matter: they still go into `messages`, which is how the tail of a dying process reaches the delta.

### Plan mode and queued messages

Codex plans per turn, with an interaction mode on each message. Claude Code and Grok plan per
chat, through the permission mode. `AgentSwitchWorkMode.decide` looks at the chat's mode, the
controls the owner left in the picker, and each pending queued message that carries a mode. A
message wants Plan when it was written in Plan or the chat's permission mode is Plan.

- Where the target plans per turn (Codex), each queued message is rewritten to the mode it wanted.
  The chat's mode follows the first queued message: a chat in Plan whose first queued message
  wants Build goes to Build, and the chat keeps the mode it had only when the queue is empty.
  When the owner changed the mode in the picker in the same gesture, the picker decides.
- Where it plans per chat (Claude Code, Grok), the chat is in Plan when the owner chose Plan in the
  picker, or, when the owner changed nothing, when it already was in Plan or the first queued
  message wanted Plan. A queued message that agrees with the chat runs under it. One that
  disagrees returns to the composer with a notice, if it can.
- A message that cannot return to the composer (it carries an attachment or review comments) stays
  queued and runs under the chat's mode. A Build message left that way runs under Plan, and the
  notice says nothing about it unless something else moved.
- A Plan message that cannot return holds the chat in Plan on a per-chat provider ("held in
  Plan") when it is not the first queued message and the first one wants Build, or when the owner
  picked Build in the same gesture. When it is the first queued message, the chat gains Plan
  instead, with the notice below. Either way it never runs in Build.
- A chat that gains Plan only because its next queued message was written in Plan is told so.
  A chat that was already in Plan and stays there is told nothing.
- A request of the app (`AppRequest`) is never the owner's to take back: it stays queued, hidden, and
  never returns to the composer. It does not decide the chat's mode, so "the first queued message"
  above means the first one the owner wrote. One sent in Plan still never runs in Build, so it holds
  a per-chat provider in Plan, and on a provider without Plan the agent refuses it and it draws its
  retry and delete row.
- Where the target has no Plan (a Codex version without it), the chat goes to Build with a
  warning. A Plan message that cannot return stays queued in Plan and the agent refuses it
  visibly, with a warning that says so. It never runs in Build with a Plan intent.

## Cursors and the delta

A segment's cursor is the last row its native session has seen. When the next prompt is sent,
everything in `messages` after the cursor is the **delta**, and it is built by
`ConversationHandoff` and put in front of the owner's message. A new segment starts at `-1`, so
its first delta is the whole conversation. A segment re-entered after the other agent ran gets
only the rows since it left.

The delta is mechanical. No model summarises, because the one that hit its limit cannot and the
one coming in should not spend a turn on it.

### What the delta holds

In priority order when the budget tightens:

1. A header: how many turns, which model ran them, and whether the last turn was interrupted.
2. The unfinished turn in full, with each tool call and its state: completed, failed, refused or
   no result recorded (it may have run). Results are cut to a line.
3. Every owner message in full.
4. The last assistant reply of each completed turn.
5. One line per tool call of completed turns, with name, target and state.
6. The worktree: branch and changed files with counts.
7. The chat id and the pointer to `chat_read` for anything cut.

Reasoning, divider rows, full tool results and attachment bytes are left out. So are the words of a
request Unified Dev sent on the owner's behalf (`AppRequest`), the report of a Run, a failed check or a request from the pull request bar:
it opens a turn as any crew message does, and it is not the owner's message, so that turn says who
sent it and gives its row for `chat_read`, ahead of the reply it led to. Every turn before the
last counts as complete. The last counts as complete only when its last `result` row is clean, which
is `subtype: success` with `is_error` not true: Codex writes `subtype: interrupted` with `is_error:
false` for a turn the owner stopped, and Grok `error_during_execution`. A last turn with no `result`,
any other one, or a stop by the usage limit is unfinished, and its replies and tool calls are given in
full.

The reading is bounded. `Store.handoffRows` reads only the kinds the delta uses, at most 100,000 of
them, and a tool call or result above 16,000 bytes comes back rewritten by SQLite: a result keeps its
id, its state, its refusal and its first 2,000 characters; a call keeps its name, its id and the first
300 characters of each field a target is read from. The rendering happens outside the `Store` actor,
on what those reads returned, so a long record does not hold up other writes.

The budget is the last context window the runner saw, counted in characters, and 128,000 characters
until it has seen one, which is always so for the first delta of a new runner. When the record does not fit, it is cut in a fixed order: earlier completed turns lose their
replies and tool calls first, then the unfinished turn's text is capped, then its older tool calls
and replies drop, then the oldest owner messages, then the worktree, and last the oldest part of
the record itself. Each cut is named in the text with the rows it covered and how to read them
with `chat_read`. The whole delta is wrapped in the same untrusted-content markers `chat_read`
uses, behind a sentence telling the agent it is history and not instruction.

### When it counts as delivered

Sending the prompt does not move the cursor. `HandoffAcknowledgement` follows the runner through a
turn and moves it when the agent has produced a **real reply**: assistant text that is not empty
and not a synthetic or API error line, or a tool call. Until then a failed attempt leaves the
cursor where it was and the next prompt carries the delta again, at the price of a repeat in the
native transcript.

A prompt that carried no delta (a steer, a mid-turn message, or a chat with nothing owed) moves
the cursor to the newest row at the end of the turn. Steers and mid-turn messages never carry a
delta, because the turn they join already did.

A resume that finds no conversation puts the cursor back to `-1`. Claude Code with `--resume` on
an id it cannot find ends the process before `init` (measured on `claude 2.1.309`), which
`SegmentResume.refused` reads. An `init` that names a different id than the one asked for
(`SegmentResume.lostHistory`) is read the same way. Codex and Grok open a new thread or session
when a resume fails and reset the cursor only after that has worked. The next send then carries
the whole conversation. `docs/PROTOCOL.md` has the measurement.

### The record of the delta, and rewind

When a delta is delivered, the segment records the `seq` of the newest owner row or request of the
app at that moment, since a request can be the prompt that carried it and can be rewound to
(`delta_prompt_seq`; in a resume turn, which adds no row of that kind, that is the previous one),
and the cursor from before it. A rewind that removes that prompt (or an earlier one) restores the
cursor, and forgets the source too when `source_received_seq` is at or after the cut, so the prompt the
owner types next carries the delta again.

A rewind also pulls every cursor back to the cut, since the rewound rows' `seq` numbers are reused.
A rewind to a turn after the one that carried the delta leaves the delta delivered.

Rewind is limited to the active segment. `Store.prepareTranscriptRewind` refuses a turn from
before the divider with `ConversationRewindError.crossesHandoff`: "This turn ran before the agent
changed, so it cannot be rewound." Only Codex chats offer Edit From Here, in the turn's file
changes sheet, and only for a turn that has a `providerTurnID`, which the Claude Code runner
never records, and the button is shown only on Codex chats (`agentKind == .codex`). The refusal is shown as a notice in the composer (`TurnHistoryNotice`), behind the sheet,
which stays open. A chat reaches it by running Codex, then Claude Code, then Codex again (two
segments, since returning to Codex enters the parked one), and choosing Edit From Here on the
first Codex turn. A change of Codex account also puts a divider before a turn.

## The limit stop and the resume

`TurnStopCause.ofLastTurn` reads the last turn of the agent that ran it and answers `.usageLimit`
or `.other`. For Claude Code it is a row of `assistantText` whose line has model `<synthetic>` and
`error: rate_limit`. `api_error: usage_limit_reached` then makes it the limit and any other `api_error`
does not. With no `api_error`, from an older CLI, it needs `is_api_error_message: true`,
`api_error_status: 429` and text starting `You've hit your` and containing `limit`. It has to be the last
output of the turn. Those are the names of the stream, which is where every stored row comes from. Other 429s, other errors and
turns the owner stopped read `.other`. The sample is in `docs/PROTOCOL.md`.

For Codex it is the turn's closing `result` row, with `is_error: true` and `codex_error:
usageLimitExceeded`. `CodexTranslation` writes `codex_error` from `turn.error.codexErrorInfo` of a
failed `turn/completed`, a typed code the app-server schema declares, so the words of the message are
never read. Any other code, a turn with no code and a turn that was not failed read `.other`, and the
result has to be the last output of the turn. Grok sends nothing that marks a limit and always reads
`.other`, so a Grok turn stopped by its limit does not resume on its own.

`InterruptedTurnResume.decide` queues a resume, a delivery of kind `interruptedTurnResume`, only
when all of these hold:

- the stop was the limit and the origin was a provider switch, or the origin was the quota offer's
  account button, which resumes whatever the cause was, with an instruction that does not claim a
  limit, unless the chat's last turn ended clean with no turn running. The button then reads
  "Move to <account>", its note says nothing is sent until the owner writes, and the chat moves with no
  resume (`QuotaAccountOffer.resumesTask`);
- the chat has a turn to resume, opened by the owner or by a crew message, a request of the app included;
- the switch was written and the queue settled;
- the owner did not press Stop since the switch began;
- the queue holds nothing else.

If the queue holds a message, the resume is not queued and the owner is told the waiting message
carries what the new agent missed. If all it holds is a request of the app, which the owner cannot
see, the same happens and the sentence names the request instead. If it already holds a resume,
nothing more happens and nobody is told anything. A sign-out moves the account with no resume. The instruction is
fixed: check the real state of the repository before repeating any action, then continue the
task.

In the transcript the resume is a line, "Resuming the interrupted task", rather than an owner
message. It is dropped when it has not started and the owner stops the agent, sends a message,
or the chat starts up again; a message typed in the meantime replaces it with a notice. One that
is already starting runs, or fails on its own. A second resume needs a second limit: a resuming
row after the limit row means that cut was already resumed. A resume that fails to start leaves
an error row.

Switching provider in the middle of a running turn stops that turn. The turn has no limit row, so
it reads `.other`: nothing is resumed, the delta goes with the owner's next message, the draft is
untouched and the queue is kept. The quota offer's button on a running turn is the exception, since
it is the owner asking for exactly that, and it resumes whatever the turn was doing.

## Roles and kinds of chat

- **Workspace chats** are the base case.
- **Orchestrators** are built again on the new provider with the same role prompt, tool guard and
  bridge registration they would get from a new orchestrator of that provider
  (`SessionRolePrompt`). An agent that cannot run workspaces (Cursor, OpenCode) is never offered
  as a target.
- **Ask Unified Dev** keeps its instructions on every provider and switches in place like a
  workspace chat.
- **Crew members and side conversations** switch on their own. Switching a parent leaves its
  children on their own provider and session.

## Opening in a new chat

The settings panel of the composer has a New chat row, for a chat that has spoken, with one entry
per other agent: "Open in a new chat with Codex". The new chat is seeded from the source and its first
prompt carries the source's whole conversation as a delta. In a workspace it is titled "<title> on
Codex"; in Ask it takes the title every new Ask conversation takes. The source keeps running and is not archived.

In a workspace the new chat is a tab of the same workspace. In Ask it opens beside the source as a
second conversation.

Fork from here, on the menu of a message in a workspace chat, opens the same kind of new chat with the
source's agent, model and settings, titled "<title> (fork)". It is seeded the same way, except that
`sessions.source_through_seq` is the seq of the message it was opened from rather than the source's
newest, so the first turn is told the conversation up to and including that message and nothing after it.

The source's id stays on the chat for good, in `sessions.source_session_id`, with the newest `seq` the
source had at the fork in `sessions.source_through_seq`. Nothing the source says after that is told, so a
turn still running on it does not read as interrupted. A fork of a fork is told its own source's rows and
not that source's source. Each segment records in `source_received_seq` whether it has been told. A segment that has not gets the source with its
next delta, so a third agent brought in later learns it too, and a segment that has is not told it
again when the chat returns to it. A turn that carried no delta records nothing. A native session that
is lost (a failed resume, a forgotten account) sets the record back to NULL along with the cursor, and
a source that has been deleted is simply no longer told. When the chat has rows of its own to be told
as well, the two share the budget, half to the chat's own record and the rest to the source.

## Spend and counters

The spend screen attributes by provider and account from the CLIs' own files and is not touched.
The counters on `sessions` are the active segment's, loaded from it when it becomes active and
saved to it when it is parked, so a Codex stretch never adds to Claude's totals.

## Not measured

- No usage-limit stop has been captured on the stream. The shape of its line is the shape of
  `Tests/fixtures/claude-turn-died-mid-response.ndjson`, a real stream capture of another API error,
  with the fields the binary (`claude 2.1.309`) writes for a limit. What stays inferred is `api_error` on
  a real line, read from the binary alone, the text of that line, taken from the transcript files, and
  the `result` line after it, which those files do not hold. The reading depends on the `assistantText` row alone, and a turn that also ended with a clean
  `result` would still be read as interrupted.
- No Codex or Grok usage-limit stop has been captured, so neither is read as a limit and neither
  resumes on its own. After one, the owner writes a message and the delta goes with it.
- What `thread/resume` or Grok's resume does under another account's home is unmeasured; both runners
  treat any failed resume the same way.

---

[Architecture](ARCHITECTURE.md) · [Protocol](PROTOCOL.md) · [Bridge](BRIDGE.md) · [Side conversations](SIDE-CONVERSATIONS.md)
