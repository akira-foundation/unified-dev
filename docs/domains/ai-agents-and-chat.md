# AI Agents & Chat

## Supported providers and how they're detected

`src-tauri/src/ai/agents/detector/` probes the local machine for usable AI coding
integrations at startup, one detector per signal:

| Provider | Detected via |
|---|---|
| Claude | `ANTHROPIC_API_KEY` in shell env/dotenv, or the `claude` CLI installed and signed in |
| OpenAI / Codex | `OPENAI_API_KEY` in shell env/dotenv |
| Gemini | `~/.gemini/oauth_creds.json` (gemini CLI's own OAuth credential file) |
| GitHub Copilot | `~/.config/github-copilot/` (Copilot CLI's own config directory) |
| Ollama | `OLLAMA_HOST` or `OLLAMA_URL` env var pointing at a local Ollama server |

Detection results feed `ai/agents/registry.rs`'s model registry, which also has hardcoded
fallback model lists per provider in case live discovery (e.g. querying installed Copilot
models) fails. Copilot-backed models are prefixed `copilot:*` in the model ID to
distinguish them from a native Anthropic/OpenAI call using the same underlying model
family.

## Chat session flow

`app/chat/session.rs::run()` is the core turn loop, used both by interactive chat (a user
typing in a thread) and by Autopilot (a silent, unattended run):

1. Load thread context - repo ID, workspace path, current branch.
2. Build the system prompt. Silent/automated modes (Autopilot, "draft PR" actions) get an
  action-specific prompt instead of the general chat prompt.
3. Load prior chat history (skipped for silent runs, to avoid the agent second-guessing
  itself against unrelated past context).
4. Call the resolved `AiProvider::complete()` with the message, history, MCP tool
  definitions, and workspace path.
5. Stream tokens back to the frontend via `emit_token()`; tool-call requests via
  `emit_tool_call()`.
6. Persist the assistant's final response to the `messages` table.

## Tool use

`ai/tools.rs` defines the built-in tool set every agent can call: `read_file`,
`write_file`, `list_files`, `run_command`, `read_git_log`, and others. Shell commands are
tokenized with a safe splitter and shell redirects (`>`, `>>`) are stripped from tool
input to prevent an agent from exfiltrating file contents via redirection.

MCP-provided tools (see [skills-and-mcp.md](skills-and-mcp.md)) are merged into the same
tool list at request time - only from MCP servers that are both enabled and currently
authenticated; disconnected servers are surfaced to the frontend separately so the UI can
prompt the user to reconnect rather than silently dropping those tools.

## Usage tracking

Every agent run pings the external billing backend's `/billing/usage` endpoint (via the
`akira_billing` SDK) with an HMAC-signed, anonymous-or-authenticated request - this is the
one piece of the old billing integration kept permanently (for aggregate user-count
metrics), independent of the removed paywall. See
[../CHANGELOG.md](../CHANGELOG.md) for the v0.12.7 removal of everything else billing-related.
