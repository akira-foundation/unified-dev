use async_trait::async_trait;
use serde_json::json;
use tauri::{AppHandle, Manager};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use std::collections::HashMap;

use crate::ai::provider::{AiProvider, AiRequest};
use crate::ai::providers::anthropic::cli_session::{build_stdin, clear_session, extract_session_id, persist_session, read_session};
use crate::ai::providers::anthropic::cli_stream::{emit_tool_result, emit_tool_use};
use crate::app::chat::stream::emit_token;
use crate::app::mcp::types::McpServer;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

pub struct AnthropicCliProvider;

pub fn find_claude_cli() -> Option<std::path::PathBuf> {
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

fn resolve_cli_model(model: &str) -> &str {
    match model {
        "claude-sonnet-latest" | "claude-sonnet" => "sonnet",
        "claude-opus-latest" | "claude-opus" => "opus",
        "claude-haiku-latest" | "claude-haiku" => "haiku",
        other => other,
    }
}

fn normalize_mcp_url(url: &str) -> String {
    if let Some(stripped) = url.strip_suffix("/sse") {
        return format!("{stripped}/mcp");
    }
    if url.ends_with("/mcp") {
        return url.to_string();
    }
    format!("{}/mcp", url.trim_end_matches('/'))
}

fn build_mcp_config(servers: &[McpServer]) -> Option<String> {
    if servers.is_empty() {
        return None;
    }

    let mut mcp_servers = serde_json::Map::new();
    for server in servers {
        let Some(ref token) = server.access_token else { continue };
        if token.is_empty() { continue }

        let url = normalize_mcp_url(&server.url);

        let entry = json!({
            "type": "http",
            "url": url,
            "headers": {
                "Authorization": format!("Bearer {token}")
            }
        });
        mcp_servers.insert(server.id.clone(), entry);
    }

    if mcp_servers.is_empty() {
        return None;
    }

    Some(json!({ "mcpServers": mcp_servers }).to_string())
}

impl AnthropicCliProvider {
    async fn run(&self, request: &AiRequest, app: &AppHandle) -> AppResult<String> {
        let claude_bin = find_claude_cli().ok_or_else(|| {
            AppError::Internal(
                "Claude CLI not found. Install it from https://claude.ai/download or ensure it is in PATH.".to_string(),
            )
        })?;

        let cli_model = resolve_cli_model(&request.model);

        let pool = app.state::<AppState>().db_pool.clone();
        let stored_session = read_session(&pool, &request.thread_id).await;
        let stdin_payload = build_stdin(request, stored_session.is_none());

        let mut cmd = tokio::process::Command::new(&claude_bin);
        cmd.arg("-p")
            .arg("--input-format").arg("stream-json")
            .arg("--output-format").arg("stream-json")
            .arg("--verbose")
            .arg("--system-prompt").arg(&request.system_prompt)
            .arg("--add-dir").arg(&request.workspace_path)
            .arg("--allowedTools").arg("Bash Read Write Edit Glob Grep LS")
            .arg("--model").arg(cli_model);

        if let Some(ref session_id) = stored_session {
            cmd.arg("--resume").arg(session_id);
        }

        if let Some(mcp_config_json) = build_mcp_config(&request.mcp_servers) {
            let tmp_path = std::env::temp_dir().join(format!("unified-mcp-{}.json", uuid::Uuid::new_v4()));
            std::fs::write(&tmp_path, &mcp_config_json).map_err(|e| {
                AppError::Internal(format!("Failed to write MCP config: {e}"))
            })?;
            cmd.arg("--mcp-config").arg(&tmp_path);
            cmd.arg("--strict-mcp-config");
            cmd.arg("--dangerously-skip-permissions");
            tokio::spawn(async move {
                tokio::time::sleep(std::time::Duration::from_secs(60)).await;
                let _ = std::fs::remove_file(&tmp_path);
            });
        }

        cmd.stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .current_dir(&request.workspace_path);

        let mut child = cmd.spawn().map_err(|e| {
            AppError::Internal(format!("Failed to spawn claude CLI: {e}"))
        })?;

        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(stdin_payload.as_bytes()).await.map_err(|e| {
                AppError::Internal(format!("Failed to write to claude CLI stdin: {e}"))
            })?;
        }

        let stdout = child.stdout.take().ok_or_else(|| {
            AppError::Internal("Failed to capture claude CLI stdout".to_string())
        })?;

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
        let mut tool_labels: HashMap<String, String> = HashMap::new();
        let mut captured_session: Option<String> = None;

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

            if captured_session.is_none() {
                if let Some(session_id) = extract_session_id(&val) {
                    captured_session = Some(session_id);
                }
            }

            match val.get("type").and_then(|t| t.as_str()) {
                Some("assistant") => {
                    if let Some(content_arr) = val
                        .get("message")
                        .and_then(|m| m.get("content"))
                        .and_then(|c| c.as_array())
                    {
                        for item in content_arr {
                            if item.get("type").and_then(|t| t.as_str()) == Some("tool_use") {
                                emit_tool_use(app, &request.thread_id, item, &mut tool_labels);
                                continue;
                            }
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
                                            emit_token(app, &request.thread_id, &buf);
                                            buf.clear();
                                            tokio::time::sleep(std::time::Duration::from_millis(8)).await;
                                        }
                                    }
                                    if !buf.is_empty() {
                                        emit_token(app, &request.thread_id, &buf);
                                    }
                                    full_response = text.to_string();
                                }
                            }
                        }
                    }
                }
                Some("user") => {
                    if let Some(content_arr) = val
                        .get("message")
                        .and_then(|m| m.get("content"))
                        .and_then(|c| c.as_array())
                    {
                        for item in content_arr {
                            if item.get("type").and_then(|t| t.as_str()) == Some("tool_result") {
                                emit_tool_result(app, &request.thread_id, item, &mut tool_labels);
                            }
                        }
                    }
                }
                Some("result") => {
                    if full_response.is_empty() {
                        if let Some(result_text) = val.get("result").and_then(|r| r.as_str()) {
                            emit_token(app, &request.thread_id, result_text);
                            full_response.push_str(result_text);
                        }
                    }
                }
                Some("error") => {
                    if stored_session.is_some() {
                        clear_session(&pool, &request.thread_id).await;
                    }
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
        if let Some(handle) = stderr_handle {
            if let Ok(stderr_text) = handle.await {
                if !stderr_text.trim().is_empty() {
                    eprintln!("[claude CLI] stderr output: {}", stderr_text.trim());
                }
            }
        }

        if full_response.is_empty() {
            if stored_session.is_some() {
                clear_session(&pool, &request.thread_id).await;
            }
            return Err(AppError::Internal(
                "Claude CLI returned an empty response.".to_string(),
            ));
        }

        if stored_session.is_none() {
            if let Some(session_id) = captured_session {
                persist_session(&pool, &request.thread_id, &session_id).await;
            }
        }

        Ok(full_response)
    }
}

#[async_trait]
impl AiProvider for AnthropicCliProvider {
    fn id(&self) -> &str {
        "anthropic_cli"
    }

    fn supports_model(&self, _model: &str) -> bool {
        false
    }

    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        self.run(&request, app).await
    }
}
