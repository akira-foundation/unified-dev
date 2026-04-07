use async_trait::async_trait;
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;

use crate::ai::credentials::read_codex_access_token;
use crate::ai::provider::{AiProvider, AiRequest};
use crate::ai::sse::stream_responses_sse;
use crate::ai::tools::{execute_tool, tool_definitions_responses, tool_label};
use crate::app::chat::stream::{emit_tool_call, StreamToolCallPayload};
use crate::app::chat::message::parse_content_to_responses_api;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;
use tauri::Manager;

pub struct OpenAiProvider;

impl OpenAiProvider {
    async fn run(&self, request: &AiRequest, app: &AppHandle) -> AppResult<String> {
        let access_token = read_codex_access_token().ok_or_else(|| {
            AppError::Internal(
                "OpenAI Codex CLI credentials not found (~/.codex/auth.json). Run `codex login` first.".to_string(),
            )
        })?;

        let client = Client::new();
        let tools = tool_definitions_responses(&request.mcp_tools);

        let mut input: Vec<Value> = vec![
            json!({ "type": "message", "role": "system", "content": request.system_prompt })
        ];
        for msg in request.history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
            input.push(json!({ "type": "message", "role": msg.role, "content": parse_content_to_responses_api(&msg.content, &msg.role) }));
        }
        input.push(json!({ "type": "message", "role": "user", "content": parse_content_to_responses_api(&request.content, "user") }));

        let mut full_text = String::new();
        let mut workspace_path = request.workspace_path.clone();

        loop {
            let max_output_tokens: u32 = if request.fast_mode { 2048 } else { 8192 };

            let body = json!({
                "model": "codex-mini-latest",
                "input": input,
                "stream": true,
                "max_output_tokens": max_output_tokens,
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
                return Err(AppError::Internal(format!("OpenAI API error {status}: {text}")));
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

                let (result, new_path) = execute_tool(&tc.name, &args, &workspace_path, &request.thread_id, &app.state::<AppState>().db_pool, &request.mcp_servers, &request.mcp_tools).await;
                if let Some(p) = new_path {
                    workspace_path = p;
                }

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
impl AiProvider for OpenAiProvider {
    fn id(&self) -> &str {
        "openai"
    }

    fn supports_model(&self, _model: &str) -> bool {
        false
    }

    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        self.run(&request, app).await
    }
}
