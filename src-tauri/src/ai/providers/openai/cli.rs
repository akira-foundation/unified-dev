use async_trait::async_trait;
use tauri::AppHandle;
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use crate::ai::provider::{AiProvider, AiRequest};
use crate::chat::stream::{emit_token, emit_tool_call, StreamToolCallPayload};
use crate::error::{AppError, AppResult};

pub struct OpenAiCliProvider;

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

impl OpenAiCliProvider {
    async fn run(&self, request: &AiRequest, app: &AppHandle) -> AppResult<String> {
        let codex_bin = find_codex_cli().ok_or_else(|| {
            AppError::Internal(
                "Codex CLI not found. Install it with: brew install codex".to_string(),
            )
        })?;

        let mut prompt_parts: Vec<String> =
            vec![format!("System: {}", request.system_prompt)];
        for msg in request.history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
            let role_label = if msg.role == "user" { "User" } else { "Assistant" };
            prompt_parts.push(format!("{role_label}: {}", msg.content));
        }
        // Always append the current user message.
        prompt_parts.push(format!("User: {}", request.content));
        let stdin_prompt = prompt_parts.join("\n\n");

        let mut cmd = tokio::process::Command::new(&codex_bin);
        cmd.arg("exec")
            .arg("--json")
            .arg("--model").arg(&request.model)
            .arg("--sandbox").arg("workspace-write")
            .arg("--ephemeral")
            .arg("-C").arg(&request.workspace_path)
            .arg("-");

        cmd.stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null());

        let mut child = cmd.spawn().map_err(|e| {
            AppError::Internal(format!("Failed to spawn codex CLI: {e}"))
        })?;

        if let Some(mut stdin) = child.stdin.take() {
            stdin.write_all(stdin_prompt.as_bytes()).await.map_err(|e| {
                AppError::Internal(format!("Failed to write to codex CLI stdin: {e}"))
            })?;
        }

        let stdout = child.stdout.take().ok_or_else(|| {
            AppError::Internal("Failed to capture codex CLI stdout".to_string())
        })?;

        let mut lines = BufReader::new(stdout).lines();
        let mut full_response = String::new();
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
                                thread_id: request.thread_id.clone(),
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
                                        let mut buf = String::new();
                                        for ch in text.chars() {
                                            buf.push(ch);
                                            if ch == ' ' || ch == '\n' || ch == ',' || ch == '.' || ch == ':' {
                                                emit_token(app, &request.thread_id, &buf);
                                                buf.clear();
                                                tokio::time::sleep(std::time::Duration::from_millis(4)).await;
                                            }
                                        }
                                        if !buf.is_empty() {
                                            emit_token(app, &request.thread_id, &buf);
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
                                        thread_id: request.thread_id.clone(),
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
}

#[async_trait]
impl AiProvider for OpenAiCliProvider {
    fn id(&self) -> &str {
        "openai_cli"
    }

    fn supports_model(&self, _model: &str) -> bool {
        // Used as a fallback; not directly selected by the registry.
        false
    }

    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        self.run(&request, app).await
    }
}
