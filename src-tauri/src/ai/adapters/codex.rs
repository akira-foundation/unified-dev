use async_trait::async_trait;
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;

use crate::ai::credentials::read_codex_access_token;
use crate::ai::provider::{AiProvider, AiRequest};
use crate::ai::sse::stream_responses_sse;
use crate::ai::tools::{execute_tool, tool_definitions_responses, tool_label};
use crate::chat::stream::{emit_tool_call, StreamToolCallPayload};
use crate::error::{AppError, AppResult};

/// Calls the OpenAI Responses API directly using the Codex CLI's stored token.
/// FIX: previously used stream_openai_sse_with_tools (chat completions parser)
///      but the endpoint is /v1/responses — now correctly uses stream_responses_sse.
pub struct CodexAdapter;

impl CodexAdapter {
    async fn run(&self, request: &AiRequest, app: &AppHandle) -> AppResult<String> {
        let access_token = read_codex_access_token().ok_or_else(|| {
            AppError::Internal(
                "OpenAI Codex CLI credentials not found (~/.codex/auth.json). Run `codex login` first.".to_string(),
            )
        })?;

        let client = Client::new();
        let tools = tool_definitions_responses();

        let mut input: Vec<Value> = vec![
            json!({ "type": "message", "role": "system", "content": request.system_prompt })
        ];
        for msg in request.history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
            input.push(json!({ "type": "message", "role": msg.role, "content": msg.content }));
        }
        // Always append the current user message after the history.
        input.push(json!({ "type": "message", "role": "user", "content": request.content }));

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
                .map_err(AppError::Http)?;

            if !response.status().is_success() {
                let status = response.status();
                let text = response.text().await.unwrap_or_default();
                return Err(AppError::Internal(format!("Codex API error {status}: {text}")));
            }

            let (text_in_turn, tool_calls) =
                stream_responses_sse(response, app, &request.thread_id).await?;

            full_text.push_str(&text_in_turn);

            if tool_calls.is_empty() {
                break;
            }

            for tc in &tool_calls {
                input.push(json!({
                    "type": "function_call",
                    "call_id": tc.call_id,
                    "name": tc.name,
                    "arguments": tc.arguments
                }));
            }

            for tc in &tool_calls {
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

                input.push(json!({
                    "type": "function_call_output",
                    "call_id": tc.call_id,
                    "output": result
                }));
            }
        }

        Ok(full_text)
    }
}

#[async_trait]
impl AiProvider for CodexAdapter {
    fn id(&self) -> &str {
        "codex"
    }

    fn supports_model(&self, _model: &str) -> bool {
        // Only used as a direct fallback; never selected by the registry.
        false
    }

    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        self.run(&request, app).await
    }
}
