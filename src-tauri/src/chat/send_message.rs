use futures_util::StreamExt;
use reqwest::Client;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::SqlitePool;
use tauri::AppHandle;
use tokio::io::{AsyncBufReadExt, BufReader};

use crate::error::{AppError, AppResult};

use super::messages::{get_messages, save_message, Message};
use super::stream::{emit_done, emit_error, emit_token, emit_tool_call, StreamToolCallPayload};

// ---------------------------------------------------------------------------
// SSE / response types
// ---------------------------------------------------------------------------

/// Anthropic streaming event (kept for reference but parsing is done via raw Value).
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct AnthropicSseEvent {
    #[serde(rename = "type")]
    event_type: String,
    delta: Option<AnthropicSseDelta>,
    index: Option<usize>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct AnthropicSseDelta {
    #[serde(rename = "type")]
    delta_type: Option<String>,
    text: Option<String>,
    // For tool_use blocks
    partial_json: Option<String>,
}

/// Anthropic non-streaming message response (kept for reference).
#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct AnthropicMessage {
    #[serde(rename = "type")]
    msg_type: String,
    content: Vec<AnthropicContentBlock>,
    stop_reason: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize, Clone)]
struct AnthropicContentBlock {
    #[serde(rename = "type")]
    block_type: String,
    // text block
    text: Option<String>,
    // tool_use block
    id: Option<String>,
    name: Option<String>,
    input: Option<Value>,
}

/// OpenAI-compatible streaming delta (used for both Copilot and Codex).
#[derive(Debug, Deserialize)]
struct OpenAiChunk {
    choices: Option<Vec<OpenAiChoice>>,
    // Codex Responses API uses `output` instead of `choices`.
    output: Option<Vec<CodexOutput>>,
}

#[derive(Debug, Deserialize)]
struct OpenAiChoice {
    delta: Option<OpenAiDelta>,
    finish_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
struct OpenAiDelta {
    content: Option<String>,
    tool_calls: Option<Vec<OpenAiToolCallDelta>>,
}

#[derive(Debug, Deserialize, Clone, Default)]
struct OpenAiToolCallDelta {
    index: Option<usize>,
    id: Option<String>,
    function: Option<OpenAiFunctionDelta>,
}

#[derive(Debug, Deserialize, Clone, Default)]
struct OpenAiFunctionDelta {
    name: Option<String>,
    arguments: Option<String>,
}

#[allow(dead_code)]
#[derive(Debug, Deserialize)]
struct CodexOutput {
    #[serde(rename = "type")]
    output_type: Option<String>,
    content: Option<Vec<CodexContent>>,
    // output_text delta format
    text: Option<String>,
}

#[derive(Debug, Deserialize)]
struct CodexContent {
    #[serde(rename = "type")]
    content_type: Option<String>,
    text: Option<String>,
}

// Accumulated tool call from streaming deltas
#[derive(Default, Clone)]
struct PendingToolCall {
    id: String,
    name: String,
    arguments: String,
}

// ---------------------------------------------------------------------------
// Thread / repo context helpers
// ---------------------------------------------------------------------------

#[derive(Debug)]
struct ThreadContext {
    repo_id: String,
    workspace_path: String,
    branch: String,
}

#[derive(Debug)]
struct RepoContext {
    name: String,
}

async fn load_thread_context(thread_id: &str, pool: &SqlitePool) -> AppResult<ThreadContext> {
    let row = sqlx::query_as::<_, (String, String, String)>(
        "SELECT repo_id, workspace_path, branch FROM threads WHERE id = ?",
    )
    .bind(thread_id)
    .fetch_optional(pool)
    .await?;

    let (repo_id, workspace_path, branch) = row.ok_or_else(|| {
        AppError::Internal(format!("Thread '{}' not found", thread_id))
    })?;

    Ok(ThreadContext { repo_id, workspace_path, branch })
}

async fn load_repo_context(repo_id: &str, pool: &SqlitePool) -> AppResult<RepoContext> {
    let row = sqlx::query_as::<_, (String,)>(
        "SELECT name FROM local_repositories WHERE id = ?",
    )
    .bind(repo_id)
    .fetch_optional(pool)
    .await?;

    let (name,) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    Ok(RepoContext { name })
}

// ---------------------------------------------------------------------------
// Credential resolution helpers
// ---------------------------------------------------------------------------

/// Resolves an environment variable by name, falling back to scanning common
/// shell init files. Tauri desktop apps do not inherit shell env vars set in
/// `.zshrc` / `.bashrc` etc. when launched from the Dock.
fn resolve_env_key(key: &str) -> Option<String> {
    if let Ok(val) = std::env::var(key) {
        if !val.is_empty() {
            return Some(val);
        }
    }

    let home = dirs::home_dir()?;
    let candidates = [
        home.join(".zshenv"),
        home.join(".zprofile"),
        home.join(".zshrc"),
        home.join(".bash_profile"),
        home.join(".bashrc"),
        home.join(".profile"),
    ];

    for path in &candidates {
        if let Ok(content) = std::fs::read_to_string(path) {
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with('#') {
                    continue;
                }
                let after_export = if trimmed.starts_with("export ") {
                    trimmed["export ".len()..].trim_start()
                } else {
                    trimmed
                };
                if after_export.starts_with(key) {
                    let rest = &after_export[key.len()..];
                    if let Some(val_str) = rest.strip_prefix('=') {
                        let val = val_str.trim().trim_matches('"').trim_matches('\'');
                        if !val.is_empty() {
                            return Some(val.to_string());
                        }
                    }
                }
            }
        }
    }

    None
}

/// Reads the GitHub Copilot OAuth token from `~/.config/github-copilot/apps.json`.
fn read_copilot_oauth_token() -> Option<String> {
    let home = dirs::home_dir()?;
    let path = home.join(".config/github-copilot/apps.json");
    let content = std::fs::read_to_string(path).ok()?;
    let map: serde_json::Value = serde_json::from_str(&content).ok()?;
    let obj = map.as_object()?;
    let mut fallback: Option<String> = None;
    for (_, entry) in obj {
        if let Some(token) = entry.get("oauth_token").and_then(|t| t.as_str()) {
            if token.starts_with("ghu_") {
                return Some(token.to_string());
            }
            fallback = Some(token.to_string());
        }
    }
    fallback
}

/// Exchanges the Copilot OAuth token for a short-lived Copilot API token.
async fn exchange_copilot_token(oauth_token: &str) -> AppResult<String> {
    let client = Client::new();
    let resp = client
        .get("https://api.github.com/copilot_internal/v2/token")
        .header("Authorization", format!("token {oauth_token}"))
        .header("User-Agent", "unified-dev/1.0")
        .send()
        .await
        .map_err(|e| AppError::Http(e))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!(
            "Copilot token exchange failed {status}: {body}"
        )));
    }

    #[derive(Deserialize)]
    struct TokenResp {
        token: String,
    }

    let parsed: TokenResp = resp
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("Copilot token parse error: {e}")))?;

    Ok(parsed.token)
}

/// Reads the OpenAI Codex CLI access token from `~/.codex/auth.json`.
fn read_codex_access_token() -> Option<String> {
    let home = dirs::home_dir()?;
    let path = home.join(".codex/auth.json");
    let content = std::fs::read_to_string(path).ok()?;
    let val: serde_json::Value = serde_json::from_str(&content).ok()?;
    val.get("tokens")
        .and_then(|t| t.get("access_token"))
        .and_then(|t| t.as_str())
        .filter(|t| !t.is_empty())
        .map(|t| t.to_string())
}

// ---------------------------------------------------------------------------
// Model ID normalisation
// ---------------------------------------------------------------------------

fn resolve_anthropic_model_id(model: &str) -> &str {
    match model {
        "claude-sonnet" => "claude-sonnet-latest",
        "claude-opus"   => "claude-opus-latest",
        "claude-haiku"  => "claude-haiku-latest",
        other => other,
    }
}

fn resolve_claude_cli_model(model: &str) -> &str {
    match model {
        "claude-sonnet-latest" | "claude-sonnet" => "sonnet",
        "claude-opus-latest"   | "claude-opus"   => "opus",
        "claude-haiku-latest"  | "claude-haiku"  => "haiku",
        other => other,
    }
}

// ---------------------------------------------------------------------------
// Tool definitions (shared across providers)
// ---------------------------------------------------------------------------

fn tool_definitions_anthropic() -> Value {
    json!([
        {
            "name": "read_file",
            "description": "Read the contents of a file in the workspace. Use this to examine source code, config files, or any text file.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the file, relative to the workspace root (e.g. 'src/helpers.php')."
                    }
                },
                "required": ["path"]
            }
        },
        {
            "name": "write_file",
            "description": "Write or overwrite a file in the workspace with new content. Use this to apply code changes.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Path to the file, relative to the workspace root."
                    },
                    "content": {
                        "type": "string",
                        "description": "Full content to write to the file."
                    }
                },
                "required": ["path", "content"]
            }
        },
        {
            "name": "list_files",
            "description": "List files and directories at a given path in the workspace.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Directory path relative to workspace root. Use '.' for root."
                    }
                },
                "required": ["path"]
            }
        },
        {
            "name": "run_command",
            "description": "Run a read-only shell command in the workspace directory. Allowed commands: git status, git diff, git log, git branch, git show. Do NOT use this to write files — use write_file instead.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "command": {
                        "type": "string",
                        "description": "The shell command to run (e.g. 'git diff HEAD~1')."
                    }
                },
                "required": ["command"]
            }
        },
        {
            "name": "search_in_file",
            "description": "Search for a pattern (plain text or regex) in a file and return matching lines with line numbers.",
            "input_schema": {
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "File path relative to workspace root."
                    },
                    "pattern": {
                        "type": "string",
                        "description": "Text or regex pattern to search for."
                    }
                },
                "required": ["path", "pattern"]
            }
        }
    ])
}

fn tool_definitions_openai() -> Value {
    json!([
        {
            "type": "function",
            "function": {
                "name": "read_file",
                "description": "Read the contents of a file in the workspace.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File path relative to workspace root." }
                    },
                    "required": ["path"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "write_file",
                "description": "Write or overwrite a file in the workspace with new content.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File path relative to workspace root." },
                        "content": { "type": "string", "description": "Full content to write to the file." }
                    },
                    "required": ["path", "content"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "list_files",
                "description": "List files and directories at a given path in the workspace.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "Directory path relative to workspace root. Use '.' for root." }
                    },
                    "required": ["path"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "run_command",
                "description": "Run a read-only shell command in the workspace. Allowed: git status, git diff, git log, git branch, git show.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "command": { "type": "string", "description": "The shell command to run." }
                    },
                    "required": ["command"]
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "search_in_file",
                "description": "Search for a pattern in a file and return matching lines with line numbers.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "path": { "type": "string", "description": "File path relative to workspace root." },
                        "pattern": { "type": "string", "description": "Text or regex pattern to search for." }
                    },
                    "required": ["path", "pattern"]
                }
            }
        }
    ])
}

// ---------------------------------------------------------------------------
// Tool executor
// ---------------------------------------------------------------------------

/// Execute a tool call and return the result string.
fn execute_tool(name: &str, args: &Value, workspace_path: &str) -> String {
    let root = std::path::Path::new(workspace_path);

    match name {
        "read_file" => {
            let Some(rel) = args.get("path").and_then(|v| v.as_str()) else {
                return "Error: missing 'path' argument".to_string();
            };
            // Strip leading slash so absolute paths don't escape the workspace root.
            let rel = rel.trim_start_matches('/');
            // Reject path traversal attempts.
            if rel.contains("..") {
                return "Error: path traversal ('..') is not allowed".to_string();
            }
            let path = root.join(rel);
            eprintln!("[tool] read_file resolved path: {:?}", path);
            match std::fs::read_to_string(&path) {
                Ok(content) => {
                    // Number lines for easier reference
                    content
                        .lines()
                        .enumerate()
                        .map(|(i, line)| format!("{:>4}: {}", i + 1, line))
                        .collect::<Vec<_>>()
                        .join("\n")
                }
                Err(e) => {
                    eprintln!("[tool] read_file error on {:?}: {}", path, e);
                    format!("Error reading '{}': {}", path.display(), e)
                }
            }
        }

        "write_file" => {
            let (Some(rel), Some(content)) = (
                args.get("path").and_then(|v| v.as_str()),
                args.get("content").and_then(|v| v.as_str()),
            ) else {
                return "Error: missing 'path' or 'content' argument".to_string();
            };
            let rel = rel.trim_start_matches('/');
            if rel.contains("..") {
                return "Error: path traversal ('..') is not allowed".to_string();
            }
            let path = root.join(rel);
            // Create parent directories if needed
            if let Some(parent) = path.parent() {
                if let Err(e) = std::fs::create_dir_all(parent) {
                    return format!("Error creating directories for {rel}: {e}");
                }
            }
            match std::fs::write(&path, content) {
                Ok(_) => format!("Successfully wrote {} bytes to {rel}", content.len()),
                Err(e) => format!("Error writing {rel}: {e}"),
            }
        }

        "list_files" => {
            let rel = args.get("path").and_then(|v| v.as_str()).unwrap_or(".");
            let rel = rel.trim_start_matches('/');
            let path = root.join(rel);
            eprintln!("[tool] list_files resolved path: {:?}", path);
            match std::fs::read_dir(&path) {
                Ok(entries) => {
                    let mut items: Vec<String> = entries
                        .filter_map(|e| {
                            let e = e.ok()?;
                            let name = e.file_name().to_string_lossy().to_string();
                            let is_dir = e.file_type().ok()?.is_dir();
                            Some(if is_dir { format!("{name}/") } else { name })
                        })
                        .collect();
                    items.sort();
                    if items.is_empty() {
                        format!("{}: (empty directory)", path.display())
                    } else {
                        items.join("\n")
                    }
                }
                Err(e) => {
                    eprintln!("[tool] list_files error on {:?}: {}", path, e);
                    format!("Error listing '{}': {}", path.display(), e)
                }
            }
        }

        "run_command" => {
            let Some(cmd_str) = args.get("command").and_then(|v| v.as_str()) else {
                return "Error: missing 'command' argument".to_string();
            };

            // Safety: only allow git and a small set of read-only commands
            let allowed_prefixes = ["git status", "git diff", "git log", "git branch", "git show", "git rev-parse"];
            if !allowed_prefixes.iter().any(|p| cmd_str.trim_start().starts_with(p)) {
                return format!(
                    "Error: command not allowed. Only git read-only commands are permitted (git status, git diff, git log, git branch, git show, git rev-parse)."
                );
            }

            let parts: Vec<&str> = cmd_str.split_whitespace().collect();
            let (prog, rest) = match parts.split_first() {
                Some(s) => s,
                None => return "Error: empty command".to_string(),
            };

            match std::process::Command::new(prog)
                .args(rest)
                .current_dir(root)
                .output()
            {
                Ok(out) => {
                    let stdout = String::from_utf8_lossy(&out.stdout);
                    let stderr = String::from_utf8_lossy(&out.stderr);
                    if !out.status.success() && stdout.is_empty() {
                        format!("Exit {}: {}", out.status, stderr)
                    } else if stdout.is_empty() {
                        "(no output)".to_string()
                    } else {
                        stdout.to_string()
                    }
                }
                Err(e) => format!("Error running command: {e}"),
            }
        }

        "search_in_file" => {
            let (Some(rel), Some(pattern)) = (
                args.get("path").and_then(|v| v.as_str()),
                args.get("pattern").and_then(|v| v.as_str()),
            ) else {
                return "Error: missing 'path' or 'pattern' argument".to_string();
            };
            let path = root.join(rel);
            let content = match std::fs::read_to_string(&path) {
                Ok(c) => c,
                Err(e) => return format!("Error reading {rel}: {e}"),
            };

            let re = match regex::Regex::new(pattern) {
                Ok(r) => r,
                Err(_) => {
                    // Fall back to plain-text search
                    let matches: Vec<String> = content
                        .lines()
                        .enumerate()
                        .filter(|(_, line)| line.contains(pattern))
                        .map(|(i, line)| format!("{:>4}: {}", i + 1, line))
                        .collect();
                    if matches.is_empty() {
                        return format!("No matches for '{pattern}' in {rel}");
                    }
                    return matches.join("\n");
                }
            };

            let matches: Vec<String> = content
                .lines()
                .enumerate()
                .filter(|(_, line)| re.is_match(line))
                .map(|(i, line)| format!("{:>4}: {}", i + 1, line))
                .collect();

            if matches.is_empty() {
                format!("No matches for '{pattern}' in {rel}")
            } else {
                matches.join("\n")
            }
        }

        other => format!("Error: unknown tool '{other}'"),
    }
}

/// Build a human-readable label for a tool call event.
fn tool_label(name: &str, args: &Value) -> String {
    match name {
        "read_file" => format!(
            "read_file: {}",
            args.get("path").and_then(|v| v.as_str()).unwrap_or("?")
        ),
        "write_file" => format!(
            "write_file: {}",
            args.get("path").and_then(|v| v.as_str()).unwrap_or("?")
        ),
        "list_files" => format!(
            "list_files: {}",
            args.get("path").and_then(|v| v.as_str()).unwrap_or(".")
        ),
        "run_command" => format!(
            "run: {}",
            args.get("command").and_then(|v| v.as_str()).unwrap_or("?")
        ),
        "search_in_file" => format!(
            "search '{}' in {}",
            args.get("pattern").and_then(|v| v.as_str()).unwrap_or("?"),
            args.get("path").and_then(|v| v.as_str()).unwrap_or("?")
        ),
        other => other.to_string(),
    }
}

// ---------------------------------------------------------------------------
// System prompt builder
// ---------------------------------------------------------------------------

/// Walks `root` up to `max_depth` levels, collecting relative paths of all
/// files (skipping common noise dirs). Returns a sorted, newline-separated
/// tree string suitable for embedding in a system prompt.
fn collect_file_tree(root: &std::path::Path, max_depth: usize) -> String {
    let ignore = [
        ".git", "node_modules", "target", ".next", "dist", "build",
        ".cache", "__pycache__", ".venv", "venv", ".idea", ".vscode",
    ];

    let mut entries: Vec<String> = Vec::new();

    fn walk(
        dir: &std::path::Path,
        root: &std::path::Path,
        depth: usize,
        max_depth: usize,
        ignore: &[&str],
        entries: &mut Vec<String>,
    ) {
        if depth > max_depth {
            return;
        }
        let Ok(iter) = std::fs::read_dir(dir) else { return };
        let mut children: Vec<std::path::PathBuf> = iter
            .filter_map(|e| e.ok().map(|e| e.path()))
            .collect();
        children.sort();

        for path in children {
            let name = path.file_name().and_then(|n| n.to_str()).unwrap_or("");
            if name.starts_with('.') && name != ".env" {
                continue;
            }
            if ignore.contains(&name) {
                continue;
            }
            if let Ok(rel) = path.strip_prefix(root) {
                let rel_str = rel.to_string_lossy().to_string();
                if path.is_dir() {
                    entries.push(format!("{rel_str}/"));
                    walk(&path, root, depth + 1, max_depth, ignore, entries);
                } else {
                    entries.push(rel_str);
                }
            }
        }
    }

    walk(root, root, 0, max_depth, &ignore, &mut entries);
    entries.join("\n")
}

fn build_system_prompt(repo_name: &str, workspace_path: &str, branch: &str) -> String {
    let root = std::path::Path::new(workspace_path);
    let file_tree = collect_file_tree(root, 4);

    let tree_section = if file_tree.is_empty() {
        String::new()
    } else {
        format!("\n\nRepository file tree:\n```\n{file_tree}\n```")
    };

    format!(
        "You are an AI coding agent working on the repository '{repo_name}' (branch: {branch}).\n\
         Workspace path: {workspace_path}\n\n\
         You have tools to read and write files and run git commands. \
         ALWAYS use your tools to actually perform the requested task — never just describe what you would do. \
         When asked to modify a file, read it first, then write the changes back with write_file. \
         When asked about code, read the relevant files before answering.\
         {tree_section}"
    )
}

// ---------------------------------------------------------------------------
// Shared SSE streaming helper (OpenAI-compatible format)
// ---------------------------------------------------------------------------

/// Drives an OpenAI-compatible SSE stream. Returns the full response text
/// and any tool calls encountered. Streams text tokens to the frontend.
async fn stream_openai_sse_with_tools(
    response: reqwest::Response,
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<(String, Vec<PendingToolCall>)> {
    let mut full_response = String::new();
    let mut byte_stream = response.bytes_stream();
    let mut line_buf = String::new();
    // Accumulate tool call deltas by index
    let mut tool_calls: Vec<PendingToolCall> = Vec::new();
    let mut _finish_reason: Option<String> = None;

    'stream: while let Some(chunk) = byte_stream.next().await {
        let chunk = chunk.map_err(|e| AppError::Http(e))?;
        let text = String::from_utf8_lossy(&chunk);

        for ch in text.chars() {
            if ch == '\n' {
                let line = line_buf.trim().to_string();
                line_buf.clear();

                if let Some(data) = line.strip_prefix("data: ") {
                    if data == "[DONE]" {
                        break 'stream;
                    }

                    if let Ok(chunk) = serde_json::from_str::<OpenAiChunk>(data) {
                        // Chat completions format (Copilot / standard OpenAI).
                        if let Some(choices) = chunk.choices {
                            for choice in choices {
                                if let Some(fr) = &choice.finish_reason {
                                    _finish_reason = Some(fr.clone());
                                }
                                if let Some(delta) = choice.delta {
                                    // Text content
                                    if let Some(content) = delta.content {
                                        emit_token(app, thread_id, &content);
                                        full_response.push_str(&content);
                                    }
                                    // Tool call deltas
                                    if let Some(tc_deltas) = delta.tool_calls {
                                        for tc_delta in tc_deltas {
                                            let idx = tc_delta.index.unwrap_or(0);
                                            // Grow vec to fit index
                                            while tool_calls.len() <= idx {
                                                tool_calls.push(PendingToolCall::default());
                                            }
                                            if let Some(id) = tc_delta.id {
                                                tool_calls[idx].id = id;
                                            }
                                            if let Some(func) = tc_delta.function {
                                                if let Some(name) = func.name {
                                                    tool_calls[idx].name = name;
                                                }
                                                if let Some(args) = func.arguments {
                                                    tool_calls[idx].arguments.push_str(&args);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Codex Responses API format.
                        if let Some(outputs) = chunk.output {
                            for output in outputs {
                                if let Some(content_arr) = output.content {
                                    for item in content_arr {
                                        if item.content_type.as_deref() == Some("output_text") {
                                            if let Some(t) = item.text {
                                                emit_token(app, thread_id, &t);
                                                full_response.push_str(&t);
                                            }
                                        }
                                    }
                                }
                                if let Some(t) = output.text {
                                    emit_token(app, thread_id, &t);
                                    full_response.push_str(&t);
                                }
                            }
                        }
                    }
                }
            } else {
                line_buf.push(ch);
            }
        }
    }

    Ok((full_response, tool_calls))
}

// ---------------------------------------------------------------------------
// Anthropic agentic loop
// ---------------------------------------------------------------------------

/// Streams a response from the Anthropic Messages API with full tool-use support.
/// Runs multiple turns until the model calls `end_turn` (no more tool calls).
async fn anthropic_stream(
    model: &str,
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
    workspace_path: &str,
) -> AppResult<String> {
    let api_key = resolve_env_key("ANTHROPIC_API_KEY").ok_or_else(|| {
        AppError::Internal(
            "ANTHROPIC_API_KEY is not set. Add it to your shell config (e.g. ~/.zshrc) or environment.".to_string(),
        )
    })?;

    let api_model = resolve_anthropic_model_id(model);
    let client = Client::new();

    // Build the initial message history
    let mut messages: Vec<Value> = history
        .iter()
        .filter(|m| m.role == "user" || m.role == "assistant")
        .map(|m| json!({ "role": m.role, "content": m.content }))
        .collect();

    let tools = tool_definitions_anthropic();
    let mut full_text_response = String::new();

    // Agentic loop: keep calling until stop_reason == "end_turn"
    loop {
        let body = json!({
            "model": api_model,
            "max_tokens": 8096,
            "system": system_prompt,
            "messages": messages,
            "tools": tools,
            "stream": true
        });

        let response = client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", &api_key)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::Http(e))?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!(
                "Anthropic API error {status}: {text}"
            )));
        }

        // Stream the response, collecting text tokens and tool_use blocks
        let (text_in_turn, tool_use_blocks, stop_reason) =
            stream_anthropic_turn(response, app, thread_id).await?;

        full_text_response.push_str(&text_in_turn);

        // Add the assistant turn to conversation history
        let mut assistant_content: Vec<Value> = Vec::new();
        if !text_in_turn.is_empty() {
            assistant_content.push(json!({ "type": "text", "text": text_in_turn }));
        }
        for block in &tool_use_blocks {
            assistant_content.push(json!({
                "type": "tool_use",
                "id": block.id,
                "name": block.name,
                "input": block.input
            }));
        }
        messages.push(json!({ "role": "assistant", "content": assistant_content }));

        // If no tool calls or stop_reason is end_turn, we're done
        if tool_use_blocks.is_empty() || stop_reason.as_deref() == Some("end_turn") {
            break;
        }

        // Execute each tool call and collect results
        let mut tool_results: Vec<Value> = Vec::new();
        for block in &tool_use_blocks {
            let args = block.input.clone().unwrap_or(Value::Object(Default::default()));
            let label = tool_label(&block.name, &args);

            // Emit "running" event to frontend
            emit_tool_call(app, StreamToolCallPayload {
                thread_id: thread_id.to_string(),
                label: label.clone(),
                status: "running".to_string(),
                output: None,
            });

            let result = execute_tool(&block.name, &args, workspace_path);

            // Emit "done" event with output
            emit_tool_call(app, StreamToolCallPayload {
                thread_id: thread_id.to_string(),
                label: label.clone(),
                status: "done".to_string(),
                output: Some(result.clone()),
            });

            tool_results.push(json!({
                "type": "tool_result",
                "tool_use_id": block.id,
                "content": result
            }));
        }

        // Add tool results as a user turn and continue the loop
        messages.push(json!({ "role": "user", "content": tool_results }));
    }

    Ok(full_text_response)
}

/// Streams a single Anthropic turn, collecting text tokens and tool_use blocks.
async fn stream_anthropic_turn(
    response: reqwest::Response,
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<(String, Vec<AnthropicToolUseBlock>, Option<String>)> {
    #[derive(Default)]
    struct ToolUseAccumulator {
        id: String,
        name: String,
        json_buf: String,
        input: Option<Value>,
    }

    let mut full_text = String::new();
    let mut tool_blocks: Vec<AnthropicToolUseBlock> = Vec::new();
    // Map from block index to accumulator
    let mut accumulators: std::collections::HashMap<usize, ToolUseAccumulator> = Default::default();
    let mut stop_reason: Option<String> = None;

    let mut byte_stream = response.bytes_stream();
    let mut line_buf = String::new();

    'stream: while let Some(chunk) = byte_stream.next().await {
        let chunk = chunk.map_err(|e| AppError::Http(e))?;
        let text = String::from_utf8_lossy(&chunk);

        for ch in text.chars() {
            if ch == '\n' {
                let line = line_buf.trim().to_string();
                line_buf.clear();

                if let Some(data) = line.strip_prefix("data: ") {
                    if data == "[DONE]" {
                        break 'stream;
                    }

                    if let Ok(event) = serde_json::from_str::<Value>(data) {
                        match event.get("type").and_then(|t| t.as_str()) {
                            Some("content_block_start") => {
                                let idx = event.get("index").and_then(|i| i.as_u64()).unwrap_or(0) as usize;
                                if let Some(block) = event.get("content_block") {
                                    if block.get("type").and_then(|t| t.as_str()) == Some("tool_use") {
                                        let acc = ToolUseAccumulator {
                                            id: block.get("id").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                                            name: block.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
                                            json_buf: String::new(),
                                            input: None,
                                        };
                                        accumulators.insert(idx, acc);
                                    }
                                }
                            }
                            Some("content_block_delta") => {
                                let idx = event.get("index").and_then(|i| i.as_u64()).unwrap_or(0) as usize;
                                if let Some(delta) = event.get("delta") {
                                    match delta.get("type").and_then(|t| t.as_str()) {
                                        Some("text_delta") => {
                                            if let Some(t) = delta.get("text").and_then(|t| t.as_str()) {
                                                emit_token(app, thread_id, t);
                                                full_text.push_str(t);
                                            }
                                        }
                                        Some("input_json_delta") => {
                                            if let Some(partial) = delta.get("partial_json").and_then(|p| p.as_str()) {
                                                if let Some(acc) = accumulators.get_mut(&idx) {
                                                    acc.json_buf.push_str(partial);
                                                }
                                            }
                                        }
                                        _ => {}
                                    }
                                }
                            }
                            Some("content_block_stop") => {
                                let idx = event.get("index").and_then(|i| i.as_u64()).unwrap_or(0) as usize;
                                if let Some(mut acc) = accumulators.remove(&idx) {
                                    // Parse the accumulated JSON
                                    acc.input = serde_json::from_str(&acc.json_buf).ok();
                                    tool_blocks.push(AnthropicToolUseBlock {
                                        id: acc.id,
                                        name: acc.name,
                                        input: acc.input,
                                    });
                                }
                            }
                            Some("message_delta") => {
                                if let Some(delta) = event.get("delta") {
                                    if let Some(sr) = delta.get("stop_reason").and_then(|s| s.as_str()) {
                                        stop_reason = Some(sr.to_string());
                                    }
                                }
                            }
                            Some("message_stop") => {
                                break 'stream;
                            }
                            _ => {}
                        }
                    }
                }
            } else {
                line_buf.push(ch);
            }
        }
    }

    Ok((full_text, tool_blocks, stop_reason))
}

#[derive(Debug)]
struct AnthropicToolUseBlock {
    id: String,
    name: String,
    input: Option<Value>,
}

// ---------------------------------------------------------------------------
// Copilot / OpenAI agentic loop
// ---------------------------------------------------------------------------

async fn copilot_stream(
    model: &str,
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
    workspace_path: &str,
) -> AppResult<String> {
    let oauth_token = read_copilot_oauth_token().ok_or_else(|| {
        AppError::Internal(
            "GitHub Copilot credentials not found. Make sure the Copilot extension is installed and authenticated.".to_string(),
        )
    })?;

    let api_token = exchange_copilot_token(&oauth_token).await?;
    let client = Client::new();
    let tools = tool_definitions_openai();

    let mut messages: Vec<Value> = vec![json!({ "role": "system", "content": system_prompt })];
    for msg in history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        messages.push(json!({ "role": msg.role, "content": msg.content }));
    }

    let mut full_text = String::new();

    loop {
        let body = json!({
            "model": model,
            "messages": messages,
            "stream": true,
            "max_tokens": 4096,
            "tools": tools,
            "tool_choice": "auto"
        });

        let response = client
            .post("https://api.githubcopilot.com/chat/completions")
            .header("Authorization", format!("Bearer {api_token}"))
            .header("Copilot-Integration-Id", "vscode-chat")
            .header("Editor-Version", "vscode/1.85.0")
            .header("Editor-Plugin-Version", "copilot-chat/0.12.0")
            .header("User-Agent", "unified-dev/1.0")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::Http(e))?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!("Copilot API error {status}: {text}")));
        }

        let (text_in_turn, pending_calls) =
            stream_openai_sse_with_tools(response, app, thread_id).await?;

        full_text.push_str(&text_in_turn);

        if pending_calls.is_empty() {
            break;
        }

        // Add assistant message with tool calls
        let tool_calls_json: Vec<Value> = pending_calls.iter().map(|tc| json!({
            "id": tc.id,
            "type": "function",
            "function": { "name": tc.name, "arguments": tc.arguments }
        })).collect();
        messages.push(json!({
            "role": "assistant",
            "content": if text_in_turn.is_empty() { Value::Null } else { Value::String(text_in_turn.clone()) },
            "tool_calls": tool_calls_json
        }));

        // Execute each tool and append results
        for tc in &pending_calls {
            let args: Value = serde_json::from_str(&tc.arguments).unwrap_or(Value::Object(Default::default()));
            let label = tool_label(&tc.name, &args);

            emit_tool_call(app, StreamToolCallPayload {
                thread_id: thread_id.to_string(),
                label: label.clone(),
                status: "running".to_string(),
                output: None,
            });

            let result = execute_tool(&tc.name, &args, workspace_path);

            emit_tool_call(app, StreamToolCallPayload {
                thread_id: thread_id.to_string(),
                label: label.clone(),
                status: "done".to_string(),
                output: Some(result.clone()),
            });

            messages.push(json!({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": result
            }));
        }
    }

    Ok(full_text)
}

// ---------------------------------------------------------------------------
// Copilot Responses API agentic loop (for gpt-5.x models)
// ---------------------------------------------------------------------------

/// Streams a response via the GitHub Copilot `/v1/responses` endpoint.
/// This is a separate endpoint from `/chat/completions` and is required for
/// `gpt-5.x` Codex subscription models which reject the completions endpoint.
///
/// The Responses API SSE format uses named events:
///   response.output_text.delta        → text token (data.delta)
///   response.output_item.added        → tool call start (data.item with type=function_call)
///   response.function_call_arguments.delta → tool arg chunk (data.delta)
///   response.function_call_arguments.done  → tool call complete (data.arguments)
///   response.completed                → stream done
///
/// Tool results are submitted in the next request via `input` array items of
/// type `function_call_output` with the matching `call_id`.
async fn copilot_responses_stream(
    model: &str,
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
    workspace_path: &str,
) -> AppResult<String> {
    let oauth_token = read_copilot_oauth_token().ok_or_else(|| {
        AppError::Internal(
            "GitHub Copilot credentials not found. Make sure the Copilot extension is installed and authenticated.".to_string(),
        )
    })?;

    let api_token = exchange_copilot_token(&oauth_token).await?;
    let client = Client::new();

    // Build the initial input array in Responses API format.
    // System message becomes an item of type "message" with role "system".
    let mut input: Vec<Value> = vec![
        json!({ "type": "message", "role": "system", "content": system_prompt })
    ];
    for msg in history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        input.push(json!({ "type": "message", "role": msg.role, "content": msg.content }));
    }

    // Tool definitions in Responses API format (no wrapping "function" key).
    let tools = json!([
        {
            "type": "function",
            "name": "read_file",
            "description": "Read the contents of a file in the workspace.",
            "parameters": {
                "type": "object",
                "properties": { "path": { "type": "string", "description": "File path relative to workspace root." } },
                "required": ["path"]
            }
        },
        {
            "type": "function",
            "name": "write_file",
            "description": "Write or overwrite a file in the workspace with new content.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": { "type": "string" },
                    "content": { "type": "string" }
                },
                "required": ["path", "content"]
            }
        },
        {
            "type": "function",
            "name": "list_files",
            "description": "List files and directories at a given path in the workspace.",
            "parameters": {
                "type": "object",
                "properties": { "path": { "type": "string", "description": "Directory path relative to workspace root. Use '.' for root." } },
                "required": ["path"]
            }
        },
        {
            "type": "function",
            "name": "run_command",
            "description": "Run a read-only shell command in the workspace. Allowed: git status, git diff, git log, git branch, git show.",
            "parameters": {
                "type": "object",
                "properties": { "command": { "type": "string" } },
                "required": ["command"]
            }
        },
        {
            "type": "function",
            "name": "search_in_file",
            "description": "Search for a pattern in a file and return matching lines with line numbers.",
            "parameters": {
                "type": "object",
                "properties": {
                    "path": { "type": "string" },
                    "pattern": { "type": "string" }
                },
                "required": ["path", "pattern"]
            }
        }
    ]);

    let mut full_text = String::new();

    loop {
        let body = json!({
            "model": model,
            "input": input,
            "stream": true,
            "max_output_tokens": 8192,
            "tools": tools,
            "tool_choice": "auto"
        });

        let response = client
            .post("https://api.githubcopilot.com/v1/responses")
            .header("Authorization", format!("Bearer {api_token}"))
            .header("Copilot-Integration-Id", "vscode-chat")
            .header("Editor-Version", "vscode/1.85.0")
            .header("User-Agent", "unified-dev/1.0")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::Http(e))?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!("Copilot Responses API error {status}: {text}")));
        }

        // Parse the SSE stream.
        let (text_in_turn, tool_calls) =
            stream_responses_sse(response, app, thread_id).await?;

        full_text.push_str(&text_in_turn);

        if tool_calls.is_empty() {
            break;
        }

        // Append the assistant's function_call items to the running input so the
        // full conversation context is preserved in the next request.
        for tc in &tool_calls {
            input.push(json!({
                "type": "function_call",
                "call_id": tc.call_id,
                "name": tc.name,
                "arguments": tc.arguments
            }));
        }

        // Execute each tool call and append function_call_output items.
        for tc in &tool_calls {
            let args: Value = serde_json::from_str(&tc.arguments)
                .unwrap_or(Value::Object(Default::default()));
            let label = tool_label(&tc.name, &args);

            emit_tool_call(app, StreamToolCallPayload {
                thread_id: thread_id.to_string(),
                label: label.clone(),
                status: "running".to_string(),
                output: None,
            });

            let result = execute_tool(&tc.name, &args, workspace_path);

            emit_tool_call(app, StreamToolCallPayload {
                thread_id: thread_id.to_string(),
                label: label.clone(),
                status: "done".to_string(),
                output: Some(result.clone()),
            });

            input.push(json!({
                "type": "function_call_output",
                "call_id": tc.call_id,
                "output": result
            }));
        }
    }

    Ok(full_text)
}

/// Tracks a pending function call from the Responses API SSE stream.
#[derive(Default)]
struct ResponsesToolCall {
    call_id: String,
    name: String,
    arguments: String,
}

/// Drives a Responses API SSE stream. Returns (text, tool_calls).
async fn stream_responses_sse(
    response: reqwest::Response,
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<(String, Vec<ResponsesToolCall>)> {
    let mut full_text = String::new();
    let mut tool_calls: Vec<ResponsesToolCall> = Vec::new();
    // Index into tool_calls for the currently-streaming function call.
    let mut current_tc_index: Option<usize> = None;

    let mut byte_stream = response.bytes_stream();
    let mut line_buf = String::new();
    let mut current_event: Option<String> = None;

    'stream: while let Some(chunk) = byte_stream.next().await {
        let chunk = chunk.map_err(|e| AppError::Http(e))?;
        let text = String::from_utf8_lossy(&chunk);

        for ch in text.chars() {
            if ch == '\n' {
                let line = line_buf.trim().to_string();
                line_buf.clear();

                if line.is_empty() {
                    // Blank line = end of SSE event; reset event name.
                    current_event = None;
                    continue;
                }

                if let Some(event_name) = line.strip_prefix("event: ") {
                    current_event = Some(event_name.to_string());
                    continue;
                }

                if let Some(data) = line.strip_prefix("data: ") {
                    let event = current_event.as_deref().unwrap_or("");
                    let Ok(val) = serde_json::from_str::<Value>(data) else {
                        continue;
                    };

                    match event {
                        "response.output_text.delta" => {
                            if let Some(delta) = val.get("delta").and_then(|d| d.as_str()) {
                                emit_token(app, thread_id, delta);
                                full_text.push_str(delta);
                            }
                        }
                        "response.output_item.added" => {
                            // A new output item started — check if it's a function call.
                            if let Some(item) = val.get("item") {
                                let item_type = item.get("type").and_then(|t| t.as_str()).unwrap_or("");
                                if item_type == "function_call" {
                                    let call_id = item.get("call_id")
                                        .and_then(|v| v.as_str())
                                        .unwrap_or("")
                                        .to_string();
                                    let name = item.get("name")
                                        .and_then(|v| v.as_str())
                                        .unwrap_or("")
                                        .to_string();
                                    current_tc_index = Some(tool_calls.len());
                                    tool_calls.push(ResponsesToolCall {
                                        call_id,
                                        name,
                                        arguments: String::new(),
                                    });
                                }
                            }
                        }
                        "response.function_call_arguments.delta" => {
                            if let Some(idx) = current_tc_index {
                                if let Some(delta) = val.get("delta").and_then(|d| d.as_str()) {
                                    tool_calls[idx].arguments.push_str(delta);
                                }
                            }
                        }
                        "response.function_call_arguments.done" => {
                            // Overwrite with the complete arguments string.
                            if let Some(idx) = current_tc_index {
                                if let Some(args) = val.get("arguments").and_then(|a| a.as_str()) {
                                    tool_calls[idx].arguments = args.to_string();
                                }
                            }
                            current_tc_index = None;
                        }
                        "response.completed" => {
                            break 'stream;
                        }
                        _ => {}
                    }
                }
            } else {
                line_buf.push(ch);
            }
        }
    }

    // Convert to PendingToolCall-compatible struct (reuse id field for call_id).
    let calls: Vec<ResponsesToolCall> = tool_calls
        .into_iter()
        .filter(|tc| !tc.call_id.is_empty() && !tc.name.is_empty())
        .collect();

    Ok((full_text, calls))
}

// ---------------------------------------------------------------------------
// Codex agentic loop
// ---------------------------------------------------------------------------

async fn codex_stream(
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
    workspace_path: &str,
) -> AppResult<String> {
    let access_token = read_codex_access_token().ok_or_else(|| {
        AppError::Internal(
            "OpenAI Codex CLI credentials not found (~/.codex/auth.json). Run `codex login` first.".to_string(),
        )
    })?;

    let client = Client::new();
    let tools = tool_definitions_openai();

    let mut input: Vec<Value> = vec![json!({ "role": "system", "content": system_prompt })];
    for msg in history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        input.push(json!({ "role": msg.role, "content": msg.content }));
    }

    let mut full_text = String::new();

    loop {
        let body = json!({
            "model": "codex-mini-latest",
            "input": input,
            "stream": true,
            "tools": tools,
            "tool_choice": "auto"
        });

        let response = client
            .post("https://api.openai.com/v1/responses")
            .header("Authorization", format!("Bearer {access_token}"))
            .header("User-Agent", "unified-dev/1.0")
            .json(&body)
            .send()
            .await
            .map_err(|e| AppError::Http(e))?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            return Err(AppError::Internal(format!("Codex API error {status}: {text}")));
        }

        let (text_in_turn, pending_calls) =
            stream_openai_sse_with_tools(response, app, thread_id).await?;

        full_text.push_str(&text_in_turn);

        if pending_calls.is_empty() {
            break;
        }

        // Add assistant message with tool calls
        let tool_calls_json: Vec<Value> = pending_calls.iter().map(|tc| json!({
            "id": tc.id,
            "type": "function",
            "function": { "name": tc.name, "arguments": tc.arguments }
        })).collect();
        input.push(json!({
            "role": "assistant",
            "content": if text_in_turn.is_empty() { Value::Null } else { Value::String(text_in_turn.clone()) },
            "tool_calls": tool_calls_json
        }));

        for tc in &pending_calls {
            let args: Value = serde_json::from_str(&tc.arguments).unwrap_or(Value::Object(Default::default()));
            let label = tool_label(&tc.name, &args);

            emit_tool_call(app, StreamToolCallPayload {
                thread_id: thread_id.to_string(),
                label: label.clone(),
                status: "running".to_string(),
                output: None,
            });

            let result = execute_tool(&tc.name, &args, workspace_path);

            emit_tool_call(app, StreamToolCallPayload {
                thread_id: thread_id.to_string(),
                label: label.clone(),
                status: "done".to_string(),
                output: Some(result.clone()),
            });

            input.push(json!({
                "role": "tool",
                "tool_call_id": tc.id,
                "content": result
            }));
        }
    }

    Ok(full_text)
}

// ---------------------------------------------------------------------------
// Claude CLI subprocess (no native tool-use — uses text-based tool protocol)
// ---------------------------------------------------------------------------

/// Finds the claude CLI binary, checking common install locations.
fn find_claude_cli() -> Option<std::path::PathBuf> {
    let home = dirs::home_dir();
    let mut candidates: Vec<std::path::PathBuf> = vec![
        std::path::PathBuf::from("/usr/local/bin/claude"),
        std::path::PathBuf::from("/opt/homebrew/bin/claude"),
    ];
    if let Some(ref h) = home {
        candidates.insert(0, h.join(".local/bin/claude"));
    }
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':') {
            candidates.push(std::path::PathBuf::from(dir).join("claude"));
        }
    }
    candidates.into_iter().find(|p| p.exists())
}

/// Streams a response via the Claude CLI subprocess.
async fn claude_cli_stream(
    model: &str,
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
    workspace_path: &str,
) -> AppResult<String> {
    let claude_bin = find_claude_cli().ok_or_else(|| {
        AppError::Internal(
            "Claude CLI not found. Install it from https://claude.ai/download or ensure it is in PATH.".to_string(),
        )
    })?;

    let mut prompt_parts: Vec<String> = Vec::new();
    for msg in history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        let role_label = if msg.role == "user" { "Human" } else { "Assistant" };
        prompt_parts.push(format!("{}: {}", role_label, msg.content));
    }
    let stdin_prompt = if prompt_parts.is_empty() {
        "Hello".to_string()
    } else {
        prompt_parts.join("\n\n")
    };

    let mut cmd = tokio::process::Command::new(&claude_bin);
    cmd.arg("-p")
        .arg("--output-format").arg("stream-json")
        .arg("--verbose")
        .arg("--system-prompt").arg(system_prompt)
        .arg("--no-session-persistence")
        // Grant the CLI read/write access to the workspace directory
        .arg("--add-dir").arg(workspace_path)
        // Give the CLI access to all built-in tools (read, write, edit, bash, etc.)
        .arg("--allowedTools").arg("Bash Read Write Edit Glob Grep LS");

    let cli_model = resolve_claude_cli_model(model);
    cmd.arg("--model").arg(cli_model);

    cmd.stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        // Pipe stderr so errors are visible in logs instead of being silently dropped
        .stderr(std::process::Stdio::piped())
        // Set the process working directory to the workspace
        .current_dir(workspace_path);

    let mut child = cmd.spawn().map_err(|e| {
        AppError::Internal(format!("Failed to spawn claude CLI: {e}"))
    })?;

    if let Some(mut stdin) = child.stdin.take() {
        use tokio::io::AsyncWriteExt;
        stdin.write_all(stdin_prompt.as_bytes()).await.map_err(|e| {
            AppError::Internal(format!("Failed to write to claude CLI stdin: {e}"))
        })?;
    }

    let stdout = child.stdout.take().ok_or_else(|| {
        AppError::Internal("Failed to capture claude CLI stdout".to_string())
    })?;
    // Collect stderr in background so it doesn't block stdout reading.
    let stderr_handle = child.stderr.take().map(|stderr| {
        tokio::spawn(async move {
            let mut lines = BufReader::new(stderr).lines();
            let mut buf = String::new();
            while let Ok(Some(line)) = lines.next_line().await {
                eprintln!("[claude CLI stderr] {}", line);
                buf.push_str(&line);
                buf.push('\n');
            }
            buf
        })
    });

    let mut lines = BufReader::new(stdout).lines();
    let mut full_response = String::new();

    while let Some(line) = lines.next_line().await.map_err(|e| {
        AppError::Internal(format!("Error reading claude CLI output: {e}"))
    })? {
        let line = line.trim().to_string();
        if line.is_empty() {
            continue;
        }

        let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) else {
            continue;
        };

        match val.get("type").and_then(|t| t.as_str()) {
            Some("assistant") => {
                if let Some(content_arr) = val
                    .get("message")
                    .and_then(|m| m.get("content"))
                    .and_then(|c| c.as_array())
                {
                    for item in content_arr {
                        if item.get("type").and_then(|t| t.as_str()) == Some("text") {
                            if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                                let new_text = if text.len() > full_response.len() {
                                    &text[full_response.len()..]
                                } else {
                                    continue;
                                };
                                if new_text.is_empty() {
                                    continue;
                                }
                                let mut buf = String::new();
                                for ch in new_text.chars() {
                                    buf.push(ch);
                                    if ch == ' ' || ch == '\n' || ch == ',' || ch == '.' || ch == ':' {
                                        emit_token(app, thread_id, &buf);
                                        buf.clear();
                                        tokio::time::sleep(std::time::Duration::from_millis(8)).await;
                                    }
                                }
                                if !buf.is_empty() {
                                    emit_token(app, thread_id, &buf);
                                }
                                full_response = text.to_string();
                            }
                        }
                    }
                }
            }
            Some("result") => {
                if full_response.is_empty() {
                    if let Some(result_text) = val.get("result").and_then(|r| r.as_str()) {
                        emit_token(app, thread_id, result_text);
                        full_response.push_str(result_text);
                    }
                }
            }
            Some("error") => {
                let msg = val.get("error")
                    .and_then(|e| e.get("message"))
                    .and_then(|m| m.as_str())
                    .unwrap_or("unknown error from claude CLI");
                return Err(AppError::Internal(format!("Claude CLI error: {msg}")));
            }
            _ => {}
        }
    }

    let _ = child.wait().await;
    // Log any stderr output for debugging
    if let Some(handle) = stderr_handle {
        if let Ok(stderr_text) = handle.await {
            if !stderr_text.trim().is_empty() {
                eprintln!("[claude CLI] stderr output: {}", stderr_text.trim());
            }
        }
    }

    if full_response.is_empty() {
        return Err(AppError::Internal(
            "Claude CLI returned an empty response.".to_string(),
        ));
    }

    Ok(full_response)
}

// ---------------------------------------------------------------------------
// Codex CLI subprocess (gpt-5.x models via `codex exec --json`)
// ---------------------------------------------------------------------------

/// Finds the codex CLI binary, checking common install locations.
fn find_codex_cli() -> Option<std::path::PathBuf> {
    let home = dirs::home_dir();
    let mut candidates: Vec<std::path::PathBuf> = vec![
        std::path::PathBuf::from("/opt/homebrew/bin/codex"),
        std::path::PathBuf::from("/usr/local/bin/codex"),
    ];
    if let Some(ref h) = home {
        candidates.push(h.join(".local/bin/codex"));
    }
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':') {
            candidates.push(std::path::PathBuf::from(dir).join("codex"));
        }
    }
    candidates.into_iter().find(|p| p.exists())
}

/// Runs a gpt-5.x model via `codex exec --json`.
/// The Codex CLI handles auth (ChatGPT session), tool-use, and sandboxing natively.
/// We pass the full conversation as a single prompt and stream `agent_message` tokens
/// to the frontend as they complete.
async fn codex_cli_stream(
    model: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
    workspace_path: &str,
) -> AppResult<String> {
    let codex_bin = find_codex_cli().ok_or_else(|| {
        AppError::Internal(
            "Codex CLI not found. Install it with: brew install codex".to_string(),
        )
    })?;

    // Build a single prompt from the conversation history.
    // The Codex CLI is single-turn per invocation; we inline history as context.
    let mut prompt_parts: Vec<String> = Vec::new();
    for msg in history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        let role_label = if msg.role == "user" { "User" } else { "Assistant" };
        prompt_parts.push(format!("{role_label}: {}", msg.content));
    }
    let stdin_prompt = if prompt_parts.is_empty() {
        "Hello".to_string()
    } else {
        prompt_parts.join("\n\n")
    };

    let mut cmd = tokio::process::Command::new(&codex_bin);
    cmd.arg("exec")
        .arg("--json")
        .arg("--model").arg(model)
        .arg("--sandbox").arg("workspace-write")
        .arg("--ephemeral")
        .arg("-C").arg(workspace_path)
        // Read prompt from stdin
        .arg("-");

    cmd.stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());

    let mut child = cmd.spawn().map_err(|e| {
        AppError::Internal(format!("Failed to spawn codex CLI: {e}"))
    })?;

    if let Some(mut stdin) = child.stdin.take() {
        use tokio::io::AsyncWriteExt;
        stdin.write_all(stdin_prompt.as_bytes()).await.map_err(|e| {
            AppError::Internal(format!("Failed to write to codex CLI stdin: {e}"))
        })?;
    }

    let stdout = child.stdout.take().ok_or_else(|| {
        AppError::Internal("Failed to capture codex CLI stdout".to_string())
    })?;

    let mut lines = BufReader::new(stdout).lines();
    let mut full_response = String::new();
    // Track command_execution items so we can emit tool events to the frontend.
    let mut pending_command: Option<String> = None;

    while let Some(line) = lines.next_line().await.map_err(|e| {
        AppError::Internal(format!("Error reading codex CLI output: {e}"))
    })? {
        let line = line.trim().to_string();
        if line.is_empty() {
            continue;
        }

        let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) else {
            continue;
        };

        let event_type = val.get("type").and_then(|t| t.as_str()).unwrap_or("");

        match event_type {
            "item.started" => {
                if let Some(item) = val.get("item") {
                    if item.get("type").and_then(|t| t.as_str()) == Some("command_execution") {
                        let cmd_str = item.get("command")
                            .and_then(|c| c.as_str())
                            .unwrap_or("shell command")
                            .to_string();
                        pending_command = Some(cmd_str.clone());
                        emit_tool_call(app, StreamToolCallPayload {
                            thread_id: thread_id.to_string(),
                            label: format!("run: {cmd_str}"),
                            status: "running".to_string(),
                            output: None,
                        });
                    }
                }
            }
            "item.completed" => {
                if let Some(item) = val.get("item") {
                    match item.get("type").and_then(|t| t.as_str()) {
                        Some("agent_message") => {
                            if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                                if !text.is_empty() {
                                    // Emit incrementally word-by-word for a streaming feel.
                                    let mut buf = String::new();
                                    for ch in text.chars() {
                                        buf.push(ch);
                                        if ch == ' ' || ch == '\n' || ch == ',' || ch == '.' || ch == ':' {
                                            emit_token(app, thread_id, &buf);
                                            buf.clear();
                                            tokio::time::sleep(std::time::Duration::from_millis(4)).await;
                                        }
                                    }
                                    if !buf.is_empty() {
                                        emit_token(app, thread_id, &buf);
                                    }
                                    if !full_response.is_empty() {
                                        full_response.push('\n');
                                    }
                                    full_response.push_str(text);
                                }
                            }
                        }
                        Some("command_execution") => {
                            let output = item.get("aggregated_output")
                                .and_then(|o| o.as_str())
                                .unwrap_or("")
                                .to_string();
                            if let Some(cmd_str) = pending_command.take() {
                                emit_tool_call(app, StreamToolCallPayload {
                                    thread_id: thread_id.to_string(),
                                    label: format!("run: {cmd_str}"),
                                    status: "done".to_string(),
                                    output: Some(output),
                                });
                            }
                        }
                        _ => {}
                    }
                }
            }
            "error" => {
                let msg = val.get("message")
                    .and_then(|m| m.as_str())
                    .unwrap_or("unknown error from codex CLI");
                return Err(AppError::Internal(format!("Codex CLI error: {msg}")));
            }
            _ => {}
        }
    }

    let _ = child.wait().await;

    if full_response.is_empty() {
        return Err(AppError::Internal(
            "Codex CLI returned an empty response.".to_string(),
        ));
    }

    Ok(full_response)
}

// ---------------------------------------------------------------------------
// Ollama stub
// ---------------------------------------------------------------------------

async fn ollama_stub(
    model: &str,
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<String> {
    let placeholder = format!("[Ollama streaming for model '{model}' is not yet implemented]");
    emit_token(app, thread_id, &placeholder);
    Ok(placeholder)
}

// ---------------------------------------------------------------------------
// Provider router with automatic fallback
// ---------------------------------------------------------------------------

async fn route_claude_with_fallback(
    model: &str,
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
    workspace_path: &str,
) -> AppResult<String> {
    // 1. Try Anthropic API key first.
    if resolve_env_key("ANTHROPIC_API_KEY").is_some() {
        return anthropic_stream(model, system_prompt, history, app, thread_id, workspace_path).await;
    }

    // 2. Fall back to Claude CLI if installed.
    if find_claude_cli().is_some() {
        eprintln!("[router] ANTHROPIC_API_KEY not found, falling back to Claude CLI subprocess");
        return claude_cli_stream(model, system_prompt, history, app, thread_id, workspace_path).await;
    }

    // 3. Fall back to Copilot if credentials exist.
    if read_copilot_oauth_token().is_some() {
        eprintln!("[router] Claude CLI not found, falling back to GitHub Copilot");
        return copilot_stream(model, system_prompt, history, app, thread_id, workspace_path).await;
    }

    // 4. Fall back to Codex CLI if credentials exist.
    if read_codex_access_token().is_some() {
        eprintln!("[router] Copilot not available, falling back to OpenAI Codex CLI");
        return codex_stream(system_prompt, history, app, thread_id, workspace_path).await;
    }

    Err(AppError::Internal(
        "No AI provider available. Set ANTHROPIC_API_KEY in your shell config, install the Claude CLI, or install GitHub Copilot / OpenAI Codex CLI.".to_string(),
    ))
}

fn route_model(model: &str) -> &str {
    // Anthropic — always goes through the Claude fallback chain.
    if model.starts_with("claude-") {
        return "anthropic";
    }
    // gpt-5.x and codex-* models require the Responses API (/v1/responses),
    // with codex CLI as fallback.
    if model.starts_with("gpt-5") || model.starts_with("codex-") {
        return "copilot_responses";
    }
    // Everything else (gpt-4*, gemini-*, grok-*, o1/o3/o4, etc.) → Copilot chat completions.
    if model.starts_with("gpt-")
        || model.starts_with("o1")
        || model.starts_with("o3")
        || model.starts_with("o4")
        || model.starts_with("gemini-")
        || model.starts_with("grok-")
        || model.starts_with("copilot-")
    {
        return "copilot";
    }
    "ollama"
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Saves the user message, runs the agentic loop (with tool-use), then saves the
/// assistant message. Takes ownership of `pool` and `app` so they can be
/// moved into a `tokio::spawn` closure by the calling command.
pub async fn send_message(
    thread_id: String,
    content: String,
    model: String,
    pool: SqlitePool,
    app: AppHandle,
) -> AppResult<()> {
    // 1. Persist the user message.
    save_message(&thread_id, "user", &content, None, None, &pool).await?;

    // 2. Load thread and repository context.
    let thread_ctx = load_thread_context(&thread_id, &pool).await?;
    let repo_ctx = load_repo_context(&thread_ctx.repo_id, &pool).await?;

    // 3. Load conversation history (last 40, oldest-first).
    let history = get_messages(&thread_id, &pool).await?;

    // 4. Build system prompt.
    let system_prompt = build_system_prompt(
        &repo_ctx.name,
        &thread_ctx.workspace_path,
        &thread_ctx.branch,
    );

    // 5. Route to the correct provider and run the agentic loop.
    let workspace_path = thread_ctx.workspace_path.clone();
    let full_response = match route_model(&model) {
        "anthropic" => {
            route_claude_with_fallback(&model, &system_prompt, &history, &app, &thread_id, &workspace_path).await
        }
        "copilot_responses" => {
            // Primary: Copilot /v1/responses endpoint (real streaming, no external binary).
            // Fallback: codex CLI subprocess if Copilot credentials are absent or the call fails.
            if read_copilot_oauth_token().is_some() {
                let result = copilot_responses_stream(&model, &system_prompt, &history, &app, &thread_id, &workspace_path).await;
                match result {
                    Ok(text) => Ok(text),
                    Err(e) => {
                        eprintln!("[router] copilot_responses_stream failed ({e}), falling back to codex CLI");
                        codex_cli_stream(&model, &history, &app, &thread_id, &workspace_path).await
                    }
                }
            } else {
                eprintln!("[router] Copilot credentials not found, trying codex CLI for {model}");
                codex_cli_stream(&model, &history, &app, &thread_id, &workspace_path).await
            }
        }
        "copilot" => {
            if read_copilot_oauth_token().is_some() {
                copilot_stream(&model, &system_prompt, &history, &app, &thread_id, &workspace_path).await
            } else {
                Err(AppError::Internal(
                    "GitHub Copilot credentials not found. Make sure the Copilot extension is installed and authenticated.".to_string(),
                ))
            }
        }
        _ => ollama_stub(&model, &app, &thread_id).await,
    };

    match full_response {
        Ok(response_text) => {
            // 6. Persist the complete assistant response.
            save_message(
                &thread_id,
                "assistant",
                &response_text,
                Some(&model),
                None,
                &pool,
            )
            .await?;

            // 7. Signal completion to the frontend.
            emit_done(&app, &thread_id);
        }
        Err(e) => {
            emit_error(&app, &thread_id, &e.to_string());
            return Err(e);
        }
    }

    Ok(())
}
