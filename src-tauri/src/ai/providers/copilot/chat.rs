use async_trait::async_trait;
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;

use crate::ai::credentials::{exchange_copilot_token, read_copilot_oauth_token};
use crate::ai::provider::{AiProvider, AiRequest};
use crate::ai::sse::stream_openai_sse_with_tools;
use crate::ai::tools::{execute_tool, tool_definitions_openai, tool_label};
use crate::app::chat::stream::{emit_tool_call, StreamToolCallPayload};
use crate::app::support::error::{AppError, AppResult};

pub struct CopilotChatProvider;

impl CopilotChatProvider {
    async fn run(&self, request: &AiRequest, app: &AppHandle) -> AppResult<String> {
        let oauth_token = read_copilot_oauth_token().ok_or_else(|| {
            AppError::Internal(
                "GitHub Copilot credentials not found. Make sure the Copilot extension is installed and authenticated.".to_string(),
            )
        })?;

        let api_token = exchange_copilot_token(&oauth_token).await?;
        let client = Client::new();
        let tools = tool_definitions_openai();

        let mut messages: Vec<Value> =
            vec![json!({ "role": "system", "content": request.system_prompt })];
        for msg in request.history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
            messages.push(json!({ "role": msg.role, "content": msg.content }));
        }
        // Always append the current user message after the history.
        messages.push(json!({ "role": "user", "content": request.content }));

        let mut full_text = String::new();

        loop {
            let body = json!({
                "model": request.model,
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
                .map_err(AppError::Http)?;

            if !response.status().is_success() {
                let status = response.status();
                let text = response.text().await.unwrap_or_default();
                return Err(AppError::Internal(format!("Copilot API error {status}: {text}")));
            }

            let (text_in_turn, pending_calls) =
                stream_openai_sse_with_tools(response, app, &request.thread_id).await?;

            full_text.push_str(&text_in_turn);

            if pending_calls.is_empty() {
                break;
            }

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

            for tc in &pending_calls {
                let args: Value =
                    serde_json::from_str(&tc.arguments).unwrap_or(Value::Object(Default::default()));
                let label = tool_label(&tc.name, &args);

                emit_tool_call(app, StreamToolCallPayload {
                    thread_id: request.thread_id.clone(),
                    label: label.clone(),
                    status: "running".to_string(),
                    output: None,
                });

                let result = execute_tool(&tc.name, &args, &request.workspace_path);

                emit_tool_call(app, StreamToolCallPayload {
                    thread_id: request.thread_id.clone(),
                    label,
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
}

#[async_trait]
impl AiProvider for CopilotChatProvider {
    fn id(&self) -> &str {
        "copilot_chat"
    }

    fn supports_model(&self, model: &str) -> bool {
        model.starts_with("gpt-")
            || model.starts_with("o1")
            || model.starts_with("o3")
            || model.starts_with("o4")
            || model.starts_with("gemini-")
            || model.starts_with("grok-")
            || model.starts_with("copilot-")
    }

    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        self.run(&request, app).await
    }
}
