use async_trait::async_trait;
use serde::Serialize;
use serde_json::json;
use tauri::{AppHandle, Emitter};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};

use crate::ai::provider::{AiProvider, AiRequest};
use crate::app::chat::stream::emit_token;
use crate::app::mcp::types::McpServer;
use crate::app::support::error::{AppError, AppResult};

#[derive(Serialize, Clone)]
pub struct CliUpdateNotice {
    pub tool: String,
    pub current: String,
    pub latest: String,
    pub command: String,
}

/// Parses a Gemini CLI update notice line like:
/// "Gemini CLI update available! 0.29.7 → 0.38.1"
fn parse_update_notice(line: &str) -> Option<CliUpdateNotice> {
    // Look for the arrow separator between versions
    let arrow_pos = line.find('→')?;
    let latest = line[arrow_pos + '→'.len_utf8()..].trim().to_string();

    // Find "available!" and extract the current version after it
    let after_available = line.find("available!")
        .map(|p| line[p + "available!".len()..arrow_pos].trim().to_string())?;

    if after_available.is_empty() || latest.is_empty() {
        return None;
    }

    Some(CliUpdateNotice {
        tool: "Gemini CLI".to_string(),
        current: after_available,
        latest,
        command: "brew upgrade gemini-cli".to_string(),
    })
}

pub struct GeminiCliProvider;

pub fn find_gemini_cli() -> Option<std::path::PathBuf> {
    let home = dirs::home_dir();
    let mut candidates: Vec<std::path::PathBuf> = vec![
        std::path::PathBuf::from("/usr/local/bin/gemini"),
        std::path::PathBuf::from("/opt/homebrew/bin/gemini"),
    ];
    if let Some(ref h) = home {
        candidates.insert(0, h.join(".local/bin/gemini"));
    }
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':') {
            candidates.push(std::path::PathBuf::from(dir).join("gemini"));
        }
    }
    candidates.into_iter().find(|p| p.exists())
}

pub fn has_gemini_credentials() -> bool {
    dirs::home_dir()
        .map(|h| h.join(".gemini").join("oauth_creds.json").exists())
        .unwrap_or(false)
}

fn build_conversation_stdin(request: &AiRequest) -> String {
    let mut parts: Vec<String> = Vec::new();

    if !request.system_prompt.is_empty() {
        parts.push(format!("System: {}", request.system_prompt));
    }

    for msg in request.history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
        let label = if msg.role == "user" { "User" } else { "Assistant" };
        if !msg.content.is_empty() {
            parts.push(format!("{label}: {}", msg.content));
        }
    }

    parts.join("\n\n")
}

fn build_mcp_settings(servers: &[McpServer]) -> Option<serde_json::Value> {
    if servers.is_empty() {
        return None;
    }

    let mut mcp_servers = serde_json::Map::new();
    for server in servers {
        let Some(ref token) = server.access_token else { continue };
        if token.is_empty() { continue }

        let (url, transport) = if server.url.ends_with("/sse") {
            (server.url.clone(), "sse")
        } else if server.url.ends_with("/mcp") {
            (server.url.clone(), "http")
        } else {
            (format!("{}/mcp", server.url.trim_end_matches('/')), "http")
        };

        let entry = json!({
            "url": url,
            "type": transport,
            "headers": {
                "Authorization": format!("Bearer {token}")
            }
        });
        mcp_servers.insert(server.id.clone(), entry);
    }

    if mcp_servers.is_empty() {
        return None;
    }

    Some(json!({ "mcpServers": mcp_servers }))
}

impl GeminiCliProvider {
    async fn run(&self, request: &AiRequest, app: &AppHandle) -> AppResult<String> {
        let gemini_bin = find_gemini_cli().ok_or_else(|| {
            AppError::Internal(
                "Gemini CLI not found. Install it with: brew install gemini-cli".to_string(),
            )
        })?;

        let conversation_stdin = build_conversation_stdin(request);

        let tmp_dir = std::env::temp_dir().join(format!("unified-gemini-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&tmp_dir).map_err(|e| {
            AppError::Internal(format!("Failed to create temp dir for Gemini: {e}"))
        })?;

        if let Some(settings) = build_mcp_settings(&request.mcp_servers) {
            let gemini_cfg_dir = tmp_dir.join(".gemini");
            std::fs::create_dir_all(&gemini_cfg_dir).map_err(|e| {
                AppError::Internal(format!("Failed to create .gemini dir: {e}"))
            })?;
            std::fs::write(gemini_cfg_dir.join("settings.json"), settings.to_string())
                .map_err(|e| AppError::Internal(format!("Failed to write Gemini MCP settings: {e}")))?;
        }

        let tmp_dir_clone = tmp_dir.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_secs(300)).await;
            let _ = std::fs::remove_dir_all(&tmp_dir_clone);
        });

        let mut cmd = tokio::process::Command::new(&gemini_bin);
        cmd.arg("-p").arg(&request.content)
            .arg("-o").arg("stream-json")
            .arg("-m").arg(&request.model)
            .arg("--yolo")
            .arg("--include-directories").arg(&request.workspace_path);

        cmd.stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .current_dir(&tmp_dir);

        let mut child = cmd.spawn().map_err(|e| {
            AppError::Internal(format!("Failed to spawn Gemini CLI: {e}"))
        })?;

        if !conversation_stdin.is_empty() {
            if let Some(mut stdin) = child.stdin.take() {
                stdin.write_all(conversation_stdin.as_bytes()).await.map_err(|e| {
                    AppError::Internal(format!("Failed to write to Gemini CLI stdin: {e}"))
                })?;
            }
        } else {
            drop(child.stdin.take());
        }

        let stdout = child.stdout.take().ok_or_else(|| {
            AppError::Internal("Failed to capture Gemini CLI stdout".to_string())
        })?;

        let app_handle = app.clone();
        let stderr_handle = child.stderr.take().map(|stderr| {
            tokio::spawn(async move {
                let mut lines = BufReader::new(stderr).lines();
                let mut buf = String::new();
                while let Ok(Some(line)) = lines.next_line().await {
                    if line.contains("[ImportProcessor]") || line.contains("YOLO mode") || line.contains("Session cleanup") || line.contains("cached credentials") {
                        continue;
                    }
                    if line.contains("update available") && line.contains("Gemini CLI") {
                        if let Some(notice) = parse_update_notice(&line) {
                            let _ = app_handle.emit("app-update-available", notice.clone());
                            let payload = serde_json::to_string(&notice).ok();
                            let _ = crate::app::notifications::notify(
                                &app_handle,
                                crate::app::notifications::NotificationInput {
                                    category: crate::app::notifications::NotificationCategory::Update,
                                    severity: crate::app::notifications::NotificationSeverity::Info,
                                    title: format!("{} update available", notice.tool),
                                    body: Some(format!("{} → {} ({})", notice.current, notice.latest, notice.command)),
                                    action_type: Some("update.cli".to_string()),
                                    action_payload: payload,
                                    ttl_days: Some(7),
                                },
                            )
                            .await;
                        }
                        continue;
                    }
                    if line.contains("brew upgrade gemini-cli") || line.contains("npm install") {
                        continue;
                    }
                    buf.push_str(&line);
                    buf.push('\n');
                }
                buf
            })
        });

        let mut reader = BufReader::new(stdout).lines();
        let mut full_response = String::new();

        while let Some(line) = reader.next_line().await.map_err(|e| {
            AppError::Internal(format!("Error reading Gemini CLI output: {e}"))
        })? {
            let line = line.trim().to_string();
            if line.is_empty() {
                continue;
            }

            let Ok(val) = serde_json::from_str::<serde_json::Value>(&line) else {
                continue;
            };

            match val.get("type").and_then(|t| t.as_str()) {
                Some("message") => {
                    let role = val.get("role").and_then(|r| r.as_str()).unwrap_or("");
                    let is_delta = val.get("delta").and_then(|d| d.as_bool()).unwrap_or(false);

                    if role == "assistant" && is_delta {
                        if let Some(content) = val.get("content").and_then(|c| c.as_str()) {
                            // Gemini sends the cumulative text — emit only the new portion
                            let new_text = if content.len() > full_response.len() {
                                &content[full_response.len()..]
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

                            full_response = content.to_string();
                        }
                    }
                }
                Some("result") => {
                    let status = val.get("status").and_then(|s| s.as_str()).unwrap_or("");
                    if status == "error" {
                        let msg = val.get("error")
                            .and_then(|e| e.get("message"))
                            .and_then(|m| m.as_str())
                            .unwrap_or("unknown error from Gemini CLI");
                        return Err(AppError::Internal(format!("Gemini CLI error: {msg}")));
                    }
                }
                _ => {}
            }
        }

        let _ = child.wait().await;
        let _ = std::fs::remove_dir_all(&tmp_dir);

        if let Some(handle) = stderr_handle {
            let _ = handle.await;
        }

        if full_response.is_empty() {
            return Err(AppError::Internal(
                "Gemini CLI returned an empty response.".to_string(),
            ));
        }

        Ok(full_response)
    }
}

#[async_trait]
impl AiProvider for GeminiCliProvider {
    fn id(&self) -> &str {
        "gemini_cli"
    }

    fn supports_model(&self, _model: &str) -> bool {
        false
    }

    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        self.run(&request, app).await
    }
}
