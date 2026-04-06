use async_trait::async_trait;
use reqwest::Client;
use serde_json::{json, Value};
use tauri::AppHandle;

use crate::ai::credentials::resolve_env_key;
use crate::ai::provider::{AiProvider, AiRequest};
use crate::ai::sse::stream_anthropic_turn;
use crate::ai::tools::{execute_tool, tool_definitions_anthropic, tool_label};
use crate::app::chat::stream::{emit_tool_call, StreamToolCallPayload};
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;
use tauri::Manager;

pub struct AnthropicProvider;

fn resolve_model_id(model: &str) -> &str {
    match model {
        "claude-sonnet" => "claude-sonnet-latest",
        "claude-opus" => "claude-opus-latest",
        "claude-haiku" => "claude-haiku-latest",
        other => other,
    }
}

impl AnthropicProvider {
    async fn run(&self, request: &AiRequest, app: &AppHandle) -> AppResult<String> {
        let api_key = resolve_env_key("ANTHROPIC_API_KEY").ok_or_else(|| {
            AppError::Internal(
                "ANTHROPIC_API_KEY is not set. Add it to your shell config (e.g. ~/.zshrc) or environment.".to_string(),
            )
        })?;

        let api_model = resolve_model_id(&request.model);
        let client = Client::new();
        let tools = tool_definitions_anthropic(&request.mcp_tools);

        let mut messages: Vec<Value> = request
            .history
            .iter()
            .filter(|m| m.role == "user" || m.role == "assistant")
            .map(|m| json!({ "role": m.role, "content": m.content }))
            .collect();

        // Always append the current user message after the history.
        messages.push(json!({ "role": "user", "content": request.content }));

        let mut full_text = String::new();
        let mut workspace_path = request.workspace_path.clone();

        loop {
            let max_tokens: u32 = if request.fast_mode { 2048 } else { 8096 };

            let thinking_budget_tokens: Option<u32> = match request.thinking_budget.as_str() {
                "x-high" => Some(10000),
                "high"   => Some(5000),
                "medium" => Some(2000),
                "low"    => Some(500),
                _        => None,
            };

            let mut body = json!({
                "model": api_model,
                "max_tokens": max_tokens,
                "system": request.system_prompt,
                "messages": messages,
                "tools": tools,
                "stream": true
            });

            if let Some(budget) = thinking_budget_tokens {
                body["thinking"] = json!({
                    "type": "enabled",
                    "budget_tokens": budget
                });
            }

            let response = client
                .post("https://api.anthropic.com/v1/messages")
                .header("x-api-key", &api_key)
                .header("anthropic-version", "2023-06-01")
                .header("content-type", "application/json")
                .json(&body)
                .send()
                .await
                .map_err(AppError::Http)?;

            if !response.status().is_success() {
                let status = response.status();
                let text = response.text().await.unwrap_or_default();
                return Err(AppError::Internal(format!("Anthropic API error {status}: {text}")));
            }

            let (text_in_turn, tool_use_blocks, stop_reason) =
                stream_anthropic_turn(response, app, &request.thread_id).await?;

            full_text.push_str(&text_in_turn);

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

            if tool_use_blocks.is_empty() || stop_reason.as_deref() == Some("end_turn") {
                break;
            }

            let mut tool_results: Vec<Value> = Vec::new();
            for block in &tool_use_blocks {
                let args = block.input.clone().unwrap_or(Value::Object(Default::default()));
                let label = tool_label(&block.name, &args);

                emit_tool_call(app, StreamToolCallPayload {
                    thread_id: request.thread_id.clone(),
                    label: label.clone(),
                    status: "running".to_string(),
                    output: None,
                });

                let (result, new_path) = execute_tool(&block.name, &args, &workspace_path, &request.thread_id, &app.state::<AppState>().db_pool, &request.mcp_servers).await;
                if let Some(p) = new_path {
                    workspace_path = p;
                }

                emit_tool_call(app, StreamToolCallPayload {
                    thread_id: request.thread_id.clone(),
                    label,
                    status: "done".to_string(),
                    output: Some(result.clone()),
                });

                tool_results.push(json!({
                    "type": "tool_result",
                    "tool_use_id": block.id,
                    "content": result
                }));
            }

            messages.push(json!({ "role": "user", "content": tool_results }));
        }

        Ok(full_text)
    }
}

#[async_trait]
impl AiProvider for AnthropicProvider {
    fn id(&self) -> &str {
        "anthropic"
    }

    fn supports_model(&self, model: &str) -> bool {
        model.starts_with("claude-")
    }

    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        self.run(&request, app).await
    }
}
