use async_trait::async_trait;
use tauri::AppHandle;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use crate::ai::provider::{AiProvider, AiRequest};
use crate::chat::stream::emit_token;
use crate::error::{AppError, AppResult};

pub struct ClaudeCliAdapter;

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

fn resolve_cli_model(model: &str) -> &str {
    match model {
        "claude-sonnet-latest" | "claude-sonnet" => "sonnet",
        "claude-opus-latest" | "claude-opus" => "opus",
        "claude-haiku-latest" | "claude-haiku" => "haiku",
        other => other,
    }
}

impl ClaudeCliAdapter {
    async fn run(&self, request: &AiRequest, app: &AppHandle) -> AppResult<String> {
        let claude_bin = find_claude_cli().ok_or_else(|| {
            AppError::Internal(
                "Claude CLI not found. Install it from https://claude.ai/download or ensure it is in PATH.".to_string(),
            )
        })?;

        let mut prompt_parts: Vec<String> = Vec::new();
        for msg in request.history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
            let role_label = if msg.role == "user" { "Human" } else { "Assistant" };
            prompt_parts.push(format!("{}: {}", role_label, msg.content));
        }
        // Always append the current user message.
        prompt_parts.push(format!("Human: {}", request.content));
        let stdin_prompt = prompt_parts.join("\n\n");

        let cli_model = resolve_cli_model(&request.model);

        let mut cmd = tokio::process::Command::new(&claude_bin);
        cmd.arg("-p")
            .arg("--output-format").arg("stream-json")
            .arg("--verbose")
            .arg("--system-prompt").arg(&request.system_prompt)
            .arg("--no-session-persistence")
            .arg("--add-dir").arg(&request.workspace_path)
            .arg("--allowedTools").arg("Bash Read Write Edit Glob Grep LS")
            .arg("--model").arg(cli_model);

        cmd.stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .current_dir(&request.workspace_path);

        let mut child = cmd.spawn().map_err(|e| {
            AppError::Internal(format!("Failed to spawn claude CLI: {e}"))
        })?;

        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(stdin_prompt.as_bytes()).await.map_err(|e| {
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
                Some("result") => {
                    if full_response.is_empty() {
                        if let Some(result_text) = val.get("result").and_then(|r| r.as_str()) {
                            emit_token(app, &request.thread_id, result_text);
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
}

#[async_trait]
impl AiProvider for ClaudeCliAdapter {
    fn id(&self) -> &str {
        "claude_cli"
    }

    fn supports_model(&self, _model: &str) -> bool {
        // Used as a fallback inside the Anthropic routing chain; not directly selected.
        false
    }

    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        self.run(&request, app).await
    }
}
