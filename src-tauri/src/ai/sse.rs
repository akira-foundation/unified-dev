use futures_util::StreamExt;
use serde::Deserialize;
use serde_json::Value;
use tauri::AppHandle;

use crate::chat::stream::emit_token;
use crate::error::{AppError, AppResult};

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

/// An accumulated tool call from Chat Completions streaming deltas.
#[derive(Default, Clone)]
pub struct PendingToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

/// An accumulated tool call from Responses API SSE.
#[derive(Default)]
pub struct ResponsesToolCall {
    pub call_id: String,
    pub name: String,
    pub arguments: String,
}

// ---------------------------------------------------------------------------
// OpenAI Chat Completions SSE deserialization types
// ---------------------------------------------------------------------------

#[derive(Debug, Deserialize)]
pub struct OpenAiChunk {
    pub choices: Option<Vec<OpenAiChoice>>,
}

#[derive(Debug, Deserialize)]
pub struct OpenAiChoice {
    pub delta: Option<OpenAiDelta>,
    pub finish_reason: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct OpenAiDelta {
    pub content: Option<String>,
    pub tool_calls: Option<Vec<OpenAiToolCallDelta>>,
}

#[derive(Debug, Deserialize, Clone, Default)]
pub struct OpenAiToolCallDelta {
    pub index: Option<usize>,
    pub id: Option<String>,
    pub function: Option<OpenAiFunctionDelta>,
}

#[derive(Debug, Deserialize, Clone, Default)]
pub struct OpenAiFunctionDelta {
    pub name: Option<String>,
    pub arguments: Option<String>,
}

// ---------------------------------------------------------------------------
// Chat Completions SSE parser
// ---------------------------------------------------------------------------

/// Drives an OpenAI Chat Completions SSE stream.
/// Returns (full_text, tool_calls).
pub async fn stream_openai_sse_with_tools(
    response: reqwest::Response,
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<(String, Vec<PendingToolCall>)> {
    let mut full_response = String::new();
    let mut byte_stream = response.bytes_stream();
    let mut line_buf = String::new();
    let mut tool_calls: Vec<PendingToolCall> = Vec::new();

    'stream: while let Some(chunk) = byte_stream.next().await {
        let chunk = chunk.map_err(AppError::Http)?;
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
                        if let Some(choices) = chunk.choices {
                            for choice in choices {
                                if let Some(delta) = choice.delta {
                                    if let Some(content) = delta.content {
                                        emit_token(app, thread_id, &content);
                                        full_response.push_str(&content);
                                    }
                                    if let Some(tc_deltas) = delta.tool_calls {
                                        for tc_delta in tc_deltas {
                                            let idx = tc_delta.index.unwrap_or(0);
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
// Responses API SSE parser
// ---------------------------------------------------------------------------

/// Drives a Responses API SSE stream (named events).
/// Returns (full_text, tool_calls).
pub async fn stream_responses_sse(
    response: reqwest::Response,
    app: &AppHandle,
    thread_id: &str,
) -> AppResult<(String, Vec<ResponsesToolCall>)> {
    let mut full_text = String::new();
    let mut tool_calls: Vec<ResponsesToolCall> = Vec::new();
    let mut current_tc_index: Option<usize> = None;

    let mut byte_stream = response.bytes_stream();
    let mut line_buf = String::new();
    let mut current_event: Option<String> = None;

    'stream: while let Some(chunk) = byte_stream.next().await {
        let chunk = chunk.map_err(AppError::Http)?;
        let text = String::from_utf8_lossy(&chunk);

        for ch in text.chars() {
            if ch == '\n' {
                let line = line_buf.trim().to_string();
                line_buf.clear();

                if line.is_empty() {
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

    let calls = tool_calls
        .into_iter()
        .filter(|tc| !tc.call_id.is_empty() && !tc.name.is_empty())
        .collect();

    Ok((full_text, calls))
}

// ---------------------------------------------------------------------------
// Anthropic SSE parser
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub struct AnthropicToolUseBlock {
    pub id: String,
    pub name: String,
    pub input: Option<Value>,
}

/// Streams a single Anthropic turn, collecting text tokens and tool_use blocks.
pub async fn stream_anthropic_turn(
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
    let mut accumulators: std::collections::HashMap<usize, ToolUseAccumulator> = Default::default();
    let mut stop_reason: Option<String> = None;

    let mut byte_stream = response.bytes_stream();
    let mut line_buf = String::new();

    'stream: while let Some(chunk) = byte_stream.next().await {
        let chunk = chunk.map_err(AppError::Http)?;
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
