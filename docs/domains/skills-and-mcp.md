# Skills & MCP

Two separate agent-extensibility mechanisms live side by side: Skills (prompt content)
and MCP (callable tools from external servers).

## Skills

A skill is a markdown prompt bundle (Anthropic's Skills format), not a tool - it's text
injected into the system prompt, not something the model calls.

`InstalledSkill` (`src-tauri/src/app/skills/types.rs`): `id`, `name`, `description`,
`enabled`, `icon_path`, `installed_at`, `source_path`, `scope` (`"global"` / `"project"`
/ `"local"`). Content is a `SKILL.md` file with YAML frontmatter (`name:`,
`description:`), parsed by `parse_frontmatter` (`app/skills/mod.rs`).

**Where skills are discovered on disk** (`skill_dirs`, `app/skills/mod.rs`), in
precedence order:

1. Workspace `.skills/` - scope `"project"`.
2. `~/.claude/skills` and `~/.codex` - scope `"local"`.
3. App-data `skills/` directory - scope `"global"`.

`load_content()` orders results `scope DESC, name`, so a project-scoped skill silently
wins over a global one sharing the same id - useful for a repo overriding a general
skill with a project-specific version.

Table: `skills` (`0007_create_skills.sql`, `scope` column added `0022_add_skills_scope.sql`).

Commands (`commands/skill.rs`): `fetch_recommended_skills`, `fetch_skills_from_repo`,
`sync_skills`, `get_skills`, `set_skill_enabled`, `set_skill_icon`, `install_skill`,
`uninstall_skill`, `list_installed_skills`.

## MCP (Model Context Protocol)

This app is an MCP *client* - it connects to external MCP servers over HTTP and merges
their tools into the agent's callable tool list.

`McpServer` (`app/mcp/types.rs`): `id`, `name`, `url`, `access_token`, `token_type`,
`enabled`. `McpTool`: the tool schema returned by the server.

**Protocol**: JSON-RPC over Streamable HTTP at `{server_url}/mcp`, protocol version
`"2025-03-26"`. Handshake: `initialize` → `notifications/initialized` → `tools/list`.
Responses can be plain JSON or `text/event-stream` (SSE) - the client
(`app/mcp/client.rs`) handles both.

**Auth**: OAuth 2.0 + PKCE (`app/mcp/oauth.rs`) - discovers
`.well-known/oauth-authorization-server` or `openid-configuration`, does dynamic client
registration if the server advertises a `registration_endpoint`, opens a local
`127.0.0.1` loopback listener to catch the redirect, exchanges the code for a token.
Tokens are stored **in plaintext** in the `mcp_servers.access_token` column - unlike VCS
provider credentials, there is no keychain involvement here.

Table: `mcp_servers` (`0023_create_mcp_servers.sql`).

Commands (`commands/mcp.rs`): `list_mcp_servers`, `add_mcp_server`, `remove_mcp_server`,
`set_mcp_server_enabled`, `connect_mcp_server`, `disconnect_mcp_server`,
`cancel_mcp_connect`.

## How both merge into a chat turn

`app/chat/session.rs` loads skill content and MCP tools/servers and passes them into
`ai::system_prompt::build_system_prompt`. Skills become prompt text; MCP tools are
appended to the fixed built-in tool array in `ai/tools.rs`
(`tool_definitions_anthropic`/`_openai`/`_responses`) after `read_file`, `write_file`,
`list_files`, `run_command`, `search_in_file`, `rename_workspace`. Dispatch for a
model-invoked MCP tool falls through `execute_tool`'s catch-all arm, which looks the tool
up by name across `mcp_tools`/`mcp_servers` and calls `mcp::call_tool`.

**Silent/action turns skip both.** When a chat run is silent (Autopilot, background
"draft PR" actions - see [autopilot.md](autopilot.md)), neither skills nor MCP tools are
loaded; a separate `build_action_system_prompt` is used instead, keeping those runs
narrowly scoped to the task at hand.

**No caching - every turn re-handshakes.** `load_tools()` re-runs `initialize` →
`tools/list` against every enabled+connected MCP server on every single chat turn. A
server that fails to respond is skipped silently (logged via `eprintln!`, not surfaced to
the model or the user) - worth knowing when a configured tool mysteriously "isn't
available" to the agent.
