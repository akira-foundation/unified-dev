use futures_util::StreamExt;
use reqwest::Client;
use serde::Deserialize;
use serde_json::json;
use sqlx::SqlitePool;
use tauri::AppHandle;
use tokio::io::{AsyncBufReadExt, BufReader};

use crate::error::{AppError, AppResult};

use super::messages::{get_messages, save_message, Message};
use super::stream::{emit_done, emit_error, emit_token};

// ---------------------------------------------------------------------------
// SSE / response types
// ---------------------------------------------------------------------------

/// Anthropic streaming event.
#[derive(Debug, Deserialize)]
struct AnthropicSseEvent {
    #[serde(rename = "type")]
    event_type: String,
    delta: Option<AnthropicSseDelta>,
}

#[derive(Debug, Deserialize)]
struct AnthropicSseDelta {
    #[serde(rename = "type")]
    delta_type: Option<String>,
    text: Option<String>,
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
}

#[derive(Debug, Deserialize)]
struct OpenAiDelta {
    content: Option<String>,
}

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
/// Returns the first oauth_token found (there may be multiple app registrations).
fn read_copilot_oauth_token() -> Option<String> {
    let home = dirs::home_dir()?;
    let path = home.join(".config/github-copilot/apps.json");
    let content = std::fs::read_to_string(path).ok()?;
    let map: serde_json::Value = serde_json::from_str(&content).ok()?;
    let obj = map.as_object()?;
    // Pick the entry whose oauth_token starts with "ghu_" (user token) preferring it
    // over "gho_" (OAuth app token) since user tokens have Copilot API access.
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
    // IDs ending in -latest are passed directly to the API.
    // Keep legacy short aliases for backwards compatibility.
    match model {
        "claude-sonnet" => "claude-sonnet-latest",
        "claude-opus"   => "claude-opus-latest",
        "claude-haiku"  => "claude-haiku-latest",
        other => other,
    }
}

/// Maps a model ID to the short alias accepted by the Claude CLI
/// (`--model sonnet`, `--model opus`, `--model haiku`).
fn resolve_claude_cli_model(model: &str) -> &str {
    match model {
        "claude-sonnet-latest" | "claude-sonnet" => "sonnet",
        "claude-opus-latest"   | "claude-opus"   => "opus",
        "claude-haiku-latest"  | "claude-haiku"  => "haiku",
        // For any explicit full model ID (e.g. "claude-sonnet-4-6"), pass it through.
        other => other,
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
        "You are an AI coding agent working on the repository '{repo_name}'.\n\
         Workspace path: {workspace_path}\n\
         Branch: {branch}\n\
         You have full access to the files in the workspace path above. \
         When the user asks about code, files, or classes, read them from disk using the paths shown in the file tree below.{tree_section}"
    )
}

// ---------------------------------------------------------------------------
// Shared SSE streaming helper (OpenAI-compatible format)
// ---------------------------------------------------------------------------

/// Drives an OpenAI-compatible SSE stream (used by both Copilot and Codex).
/// Emits tokens and returns the full response text.
async fn stream_openai_sse(
    response: reqwest::Response,
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<String> {
    let mut full_response = String::new();
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

                    if let Ok(chunk) = serde_json::from_str::<OpenAiChunk>(data) {
                        // Chat completions format (Copilot).
                        if let Some(choices) = chunk.choices {
                            for choice in choices {
                                if let Some(delta) = choice.delta {
                                    if let Some(content) = delta.content {
                                        emit_token(app, thread_id, &content);
                                        full_response.push_str(&content);
                                    }
                                }
                            }
                        }

                        // Codex Responses API format.
                        if let Some(outputs) = chunk.output {
                            for output in outputs {
                                // output_text delta events carry text directly.
                                if let Some(text) = output.text {
                                    emit_token(app, thread_id, &text);
                                    full_response.push_str(&text);
                                }
                                // message output with content array.
                                if let Some(contents) = output.content {
                                    for item in contents {
                                        if item.content_type.as_deref() == Some("output_text") {
                                            if let Some(text) = item.text {
                                                emit_token(app, thread_id, &text);
                                                full_response.push_str(&text);
                                            }
                                        }
                                    }
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

    Ok(full_response)
}

// ---------------------------------------------------------------------------
// Provider implementations
// ---------------------------------------------------------------------------

/// Streams a response from the Anthropic Messages API using an API key.
async fn anthropic_stream(
    model: &str,
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<String> {
    let api_key = resolve_env_key("ANTHROPIC_API_KEY").ok_or_else(|| {
        AppError::Internal(
            "ANTHROPIC_API_KEY is not set. Add it to your shell config (e.g. ~/.zshrc) or environment.".to_string(),
        )
    })?;

    let api_model = resolve_anthropic_model_id(model);

    let messages: Vec<serde_json::Value> = history
        .iter()
        .filter(|m| m.role == "user" || m.role == "assistant")
        .map(|m| json!({ "role": m.role, "content": m.content }))
        .collect();

    let body = json!({
        "model": api_model,
        "max_tokens": 8096,
        "system": system_prompt,
        "messages": messages,
        "stream": true
    });

    let client = Client::new();
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

    let mut full_response = String::new();
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

                    if let Ok(event) = serde_json::from_str::<AnthropicSseEvent>(data) {
                        if event.event_type == "content_block_delta" {
                            if let Some(delta) = event.delta {
                                if delta.delta_type.as_deref() == Some("text_delta") {
                                    if let Some(text_chunk) = delta.text {
                                        emit_token(app, thread_id, &text_chunk);
                                        full_response.push_str(&text_chunk);
                                    }
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

    Ok(full_response)
}

/// Streams a response via GitHub Copilot using the token stored in
/// `~/.config/github-copilot/apps.json`.
async fn copilot_stream(
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<String> {
    let oauth_token = read_copilot_oauth_token().ok_or_else(|| {
        AppError::Internal(
            "GitHub Copilot credentials not found. Make sure the Copilot extension is installed and authenticated.".to_string(),
        )
    })?;

    let api_token = exchange_copilot_token(&oauth_token).await?;

    let mut messages = vec![json!({ "role": "system", "content": system_prompt })];
    for msg in history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        messages.push(json!({ "role": msg.role, "content": msg.content }));
    }

    let body = json!({
        "model": "gpt-4o",
        "messages": messages,
        "stream": true,
        "max_tokens": 4096
    });

    let client = Client::new();
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
        return Err(AppError::Internal(format!(
            "Copilot API error {status}: {text}"
        )));
    }

    stream_openai_sse(response, app, thread_id).await
}

/// Streams a response via the OpenAI Codex CLI session token stored in
/// `~/.codex/auth.json`. Uses the `codex-mini-latest` model via the
/// Responses API.
async fn codex_stream(
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<String> {
    let access_token = read_codex_access_token().ok_or_else(|| {
        AppError::Internal(
            "OpenAI Codex CLI credentials not found (~/.codex/auth.json). Run `codex login` first.".to_string(),
        )
    })?;

    // Build input array for the Responses API.
    let mut input: Vec<serde_json::Value> = vec![
        json!({ "role": "system", "content": system_prompt })
    ];
    for msg in history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        input.push(json!({ "role": msg.role, "content": msg.content }));
    }

    let body = json!({
        "model": "codex-mini-latest",
        "input": input,
        "stream": true
    });

    let client = Client::new();
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
        return Err(AppError::Internal(format!(
            "Codex API error {status}: {text}"
        )));
    }

    stream_openai_sse(response, app, thread_id).await
}

/// Finds the claude CLI binary, checking common install locations.
fn find_claude_cli() -> Option<std::path::PathBuf> {
    // Check common locations used by the official installer.
    let home = dirs::home_dir();
    let mut candidates: Vec<std::path::PathBuf> = vec![
        std::path::PathBuf::from("/usr/local/bin/claude"),
        std::path::PathBuf::from("/opt/homebrew/bin/claude"),
    ];
    if let Some(ref h) = home {
        candidates.insert(0, h.join(".local/bin/claude"));
    }
    // Also check PATH entries.
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':') {
            candidates.push(std::path::PathBuf::from(dir).join("claude"));
        }
    }
    candidates.into_iter().find(|p| p.exists())
}

/// Streams a response via the Claude CLI subprocess (`claude -p --output-format stream-json`).
/// The CLI uses whatever authentication it has configured (claude.ai subscription, API key, etc.).
async fn claude_cli_stream(
    model: &str,
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<String> {
    let claude_bin = find_claude_cli().ok_or_else(|| {
        AppError::Internal(
            "Claude CLI not found. Install it from https://claude.ai/download or ensure it is in PATH.".to_string(),
        )
    })?;

    // Build the full conversation as a single prompt string passed via stdin.
    // The system prompt is injected via --system-prompt flag.
    // History is formatted as a simple conversation so the model has context.
    let mut prompt_parts: Vec<String> = Vec::new();
    for msg in history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        let role_label = if msg.role == "user" { "Human" } else { "Assistant" };
        prompt_parts.push(format!("{}: {}", role_label, msg.content));
    }
    // The last item in history is already the user message we just added.
    let stdin_prompt = if prompt_parts.is_empty() {
        // Fallback: should not happen as history always contains at least the current user msg.
        "Hello".to_string()
    } else {
        prompt_parts.join("\n\n")
    };

    let mut cmd = tokio::process::Command::new(&claude_bin);
    cmd.arg("-p")
        .arg("--output-format").arg("stream-json")
        .arg("--verbose")
        .arg("--system-prompt").arg(system_prompt)
        .arg("--no-session-persistence");

    // The Claude CLI accepts short aliases: sonnet, opus, haiku.
    let cli_model = resolve_claude_cli_model(model);
    cmd.arg("--model").arg(cli_model);

    cmd.stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null());

    let mut child = cmd.spawn().map_err(|e| {
        AppError::Internal(format!("Failed to spawn claude CLI: {e}"))
    })?;

    // Write the prompt to stdin then close it so the CLI knows input is done.
    if let Some(mut stdin) = child.stdin.take() {
        use tokio::io::AsyncWriteExt;
        stdin.write_all(stdin_prompt.as_bytes()).await.map_err(|e| {
            AppError::Internal(format!("Failed to write to claude CLI stdin: {e}"))
        })?;
        // stdin dropped here → EOF signalled
    }

    let stdout = child.stdout.take().ok_or_else(|| {
        AppError::Internal("Failed to capture claude CLI stdout".to_string())
    })?;

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
                // Extract text from message.content[].text.
                // The CLI emits the full accumulated text in each event, so we
                // only emit the *new* suffix since the last event to avoid duplicates.
                if let Some(content_arr) = val
                    .get("message")
                    .and_then(|m| m.get("content"))
                    .and_then(|c| c.as_array())
                {
                    for item in content_arr {
                        if item.get("type").and_then(|t| t.as_str()) == Some("text") {
                            if let Some(text) = item.get("text").and_then(|t| t.as_str()) {
                                // Only the delta (new characters) since last event.
                                let new_text = if text.len() > full_response.len() {
                                    &text[full_response.len()..]
                                } else {
                                    continue;
                                };
                                if new_text.is_empty() {
                                    continue;
                                }
                                // Emit word-by-word for a smooth typewriter effect.
                                let mut buf = String::new();
                                for ch in new_text.chars() {
                                    buf.push(ch);
                                    // Emit on word boundaries (space, newline) or punctuation.
                                    if ch == ' ' || ch == '\n' || ch == ',' || ch == '.' || ch == ':' {
                                        emit_token(app, thread_id, &buf);
                                        buf.clear();
                                        tokio::time::sleep(std::time::Duration::from_millis(8)).await;
                                    }
                                }
                                // Emit any remaining chars.
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
                // The result event contains the authoritative final text.
                // Use it only if we haven't accumulated anything (e.g. non-streaming run).
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

    // Wait for the child process to exit.
    let _ = child.wait().await;

    if full_response.is_empty() {
        return Err(AppError::Internal(
            "Claude CLI returned an empty response.".to_string(),
        ));
    }

    Ok(full_response)
}

/// Stub for Ollama streaming — not yet implemented.
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

/// Routes a Claude model request, falling back through available providers:
/// 1. Anthropic API key (env / shell config)
/// 2. Claude CLI subprocess (claude.ai subscription)
/// 3. GitHub Copilot (gpt-4o via copilot API)
/// 4. OpenAI Codex CLI (codex-mini-latest)
async fn route_claude_with_fallback(
    model: &str,
    system_prompt: &str,
    history: &[Message],
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<String> {
    // 1. Try Anthropic API key first.
    if resolve_env_key("ANTHROPIC_API_KEY").is_some() {
        return anthropic_stream(model, system_prompt, history, app, thread_id).await;
    }

    // 2. Fall back to Claude CLI if installed.
    if find_claude_cli().is_some() {
        eprintln!("[router] ANTHROPIC_API_KEY not found, falling back to Claude CLI subprocess");
        return claude_cli_stream(model, system_prompt, history, app, thread_id).await;
    }

    // 3. Fall back to Copilot if credentials exist.
    if read_copilot_oauth_token().is_some() {
        eprintln!("[router] Claude CLI not found, falling back to GitHub Copilot");
        return copilot_stream(system_prompt, history, app, thread_id).await;
    }

    // 4. Fall back to Codex CLI if credentials exist.
    if read_codex_access_token().is_some() {
        eprintln!("[router] Copilot not available, falling back to OpenAI Codex CLI");
        return codex_stream(system_prompt, history, app, thread_id).await;
    }

    Err(AppError::Internal(
        "No AI provider available. Set ANTHROPIC_API_KEY in your shell config, install the Claude CLI, or install GitHub Copilot / OpenAI Codex CLI.".to_string(),
    ))
}

fn route_model(model: &str) -> &str {
    if model.starts_with("claude-") {
        "anthropic"
    } else if model.starts_with("gpt-") || model.starts_with("copilot-") {
        "copilot"
    } else if model.starts_with("codex-") {
        "codex"
    } else {
        "ollama"
    }
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Saves the user message, streams the model response, then saves the
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

    // 5. Route to the correct provider and stream the response.
    let full_response = match route_model(&model) {
        "anthropic" => {
            route_claude_with_fallback(&model, &system_prompt, &history, &app, &thread_id).await
        }
        "copilot" => {
            if read_copilot_oauth_token().is_some() {
                copilot_stream(&system_prompt, &history, &app, &thread_id).await
            } else if read_codex_access_token().is_some() {
                codex_stream(&system_prompt, &history, &app, &thread_id).await
            } else {
                Err(AppError::Internal(
                    "No AI provider available for this model.".to_string(),
                ))
            }
        }
        "codex" => codex_stream(&system_prompt, &history, &app, &thread_id).await,
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
