# Side conversations

Use `/btw`, Reply on a selection, or the side-question button beside the composer to open a side
conversation. It opens in the inspector, in a Side tab beside Changes and the pull request, and
never covers the main transcript or its composer. `/btw Why this approach?` opens it and sends the
question. Follow-ups go to its own agent while work in the original chat continues. Starting one
selects the Side tab and shows the inspector if it was hidden. Escape goes back to the tab Side
replaced and keeps the conversation one click away, and `/btw` or Reply brings back the same one.
The close button ends it: its agent stops, its session is archived, and the next `/btw` or Reply
starts a fresh one with only the new quote, an empty transcript and context taken from the main chat
at that moment. Closing or keeping it removes the Side tab and returns to the tab it replaced.
Opening one always creates a new session. A side conversation of the same chat that was neither
closed nor kept, which is what a relaunch leaves behind when one was only hidden, is kept as a chat
at that moment rather than resumed or lost. The child inherits the parent's provider, model,
reasoning, permissions and composer settings.

**Keep as chat** gives the same conversation a regular tab. It preserves the provider session,
draft, history and any running turn. **Keep and start new** keeps the current detour as a tab and
opens another with fresh context. Closing or clearing the parent keeps its side conversation as a
chat and takes the Side tab away, so a running answer or approval request cannot become
unreachable.

Each chat has at most one side conversation, and the Side tab shows the one belonging to the chat
on screen. Switching to a chat with none takes the tab away; switching back brings it back. A side
conversation started from a pane that is not the active chat is shown until the active chat
changes. `SideConversationFocus` in Core makes that choice.

## Context

Unified Dev starts a separate provider session with a snapshot of the parent's recent conversation.
It does not resume or steer the parent's provider session. The snapshot includes user and
assistant text, bounded tool arguments and results, and the answer streaming when it was opened.
The snapshot takes up to 300 stored events and keeps the latest 32,000 characters; individual
tool records are limited to 2,000 characters. It does not include private reasoning or later
activity in the parent.

The snapshot is attached to the first provider prompt as quoted background. The editable draft,
queue and visible user bubble retain the actual question. Failed first submissions keep the
context available for retry. Codex acknowledges it after accepting the turn; the other runner
acknowledges it when the first answer or thinking block arrives. Subsequent turns resume the
child's own conversation.

## Storage and lifetime

`Session.sideConversationParentID` marks a temporary conversation. It is separate from
`parentSessionID`, which means an agent-created crew member. `TabSet` hides the temporary session
from the normal strip. Promotion clears the temporary parent column and leaves the snapshot in
the session settings for provenance. A database trigger promotes children when their parent is
archived, including replacement through `/clear` or `/close`.

The workspace owns the side conversation state and the ordinary `TranscriptModel` owns the child runner.
`SideConversationLifecycle` in Core decides what a start, a close and a keep do, including an
opening that is closed before it arrives or fails after it arrived, which is archived, and a
"Keep and start new" whose keep fails, which restores the conversation it was keeping and hands
it anything quoted meanwhile. A start waits for a close still being written, so it cannot keep
the conversation that was just closed. `InspectorTabChoice` decides which inspector tab is selected
as a side conversation starts and ends. Hiding the view stops neither agent; closing stops the side conversation's. Workspace teardown cancels pending opening tasks and
stops all its runners. The side composer excludes workspace review comments, and the native
Stop Agent command follows composer focus.
