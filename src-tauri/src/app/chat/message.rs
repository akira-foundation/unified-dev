use serde::{Deserialize, Serialize};
use serde_json::Value;
use sqlx::SqlitePool;
use uuid::Uuid;

use crate::app::support::error::AppResult;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Message {
    pub id: String,
    pub thread_id: String,
    pub role: String,
    pub model: Option<String>,
    pub content: String,
    pub metadata: Option<String>,
    pub created_at: String,
}

/// Parse a message content string into a JSON `Value` array suitable for API requests.
///
/// If the content is a JSON array (multipart), parses it and normalises any image parts
/// from the frontend format `{"type":"image","data":"...","mediaType":"..."}` into the
/// canonical Anthropic format `{"type":"image","source":{"type":"base64","media_type":"...","data":"..."}}`.
/// Plain text is wrapped in `[{"type":"text","text":"..."}]`.
pub fn parse_content_to_api(content: &str) -> Value {
    if content.starts_with('[') {
        if let Ok(Value::Array(arr)) = serde_json::from_str::<Value>(content) {
            let normalised: Vec<Value> = arr
                .into_iter()
                .map(|part| {
                    if part.get("type").and_then(|t| t.as_str()) == Some("image") {
                        if let (Some(data), Some(media_type)) = (
                            part.get("data").and_then(|v| v.as_str()),
                            part.get("mediaType").and_then(|v| v.as_str()),
                        ) {
                            return serde_json::json!({
                                "type": "image",
                                "source": {
                                    "type": "base64",
                                    "media_type": media_type,
                                    "data": data
                                }
                            });
                        }
                    }
                    part
                })
                .collect();
            return Value::Array(normalised);
        }
    }
    serde_json::json!([{ "type": "text", "text": content }])
}

/// Same as `parse_content_to_openai_api` but drops all image parts.
///
/// Use this for history messages to avoid sending large base64 payloads on
/// every turn — only the current (latest) message needs images.
pub fn parse_content_to_openai_api_text_only(content: &str) -> Value {
    let parts = parse_content_to_api(content);
    let Value::Array(arr) = parts else {
        return serde_json::json!([{ "type": "text", "text": content }]);
    };
    let text_parts: Vec<Value> = arr
        .into_iter()
        .filter(|part| part.get("type").and_then(|t| t.as_str()) != Some("image"))
        .collect();
    if text_parts.is_empty() {
        serde_json::json!([{ "type": "text", "text": "[image]" }])
    } else {
        Value::Array(text_parts)
    }
}

/// Parse a message content string into a JSON `Value` array suitable for OpenAI/Copilot API requests.
///
/// Converts Anthropic-style `{"type":"image","source":{"type":"base64","media_type":"...","data":"..."}}` parts
/// to OpenAI-style `{"type":"image_url","image_url":{"url":"data:<media_type>;base64,<data>"}}`.
pub fn parse_content_to_openai_api(content: &str) -> Value {
    let parts = parse_content_to_api(content);
    let Value::Array(arr) = parts else {
        return serde_json::json!([{ "type": "text", "text": content }]);
    };
    let converted: Vec<Value> = arr
        .into_iter()
        .map(|part| {
            if part.get("type").and_then(|t| t.as_str()) == Some("image") {
                if let Some(source) = part.get("source") {
                    let media_type = source
                        .get("media_type")
                        .and_then(|v| v.as_str())
                        .unwrap_or("image/jpeg");
                    let data = source
                        .get("data")
                        .and_then(|v| v.as_str())
                        .unwrap_or_default();
                    return serde_json::json!({
                        "type": "image_url",
                        "image_url": { "url": format!("data:{media_type};base64,{data}") }
                    });
                }
            }
            part
        })
        .collect();
    Value::Array(converted)
}

/// Parse a message content string into a JSON `Value` array suitable for the OpenAI Responses API.
///
/// The Responses API uses role-dependent type names:
/// - user text:      `{"type":"input_text","text":"..."}`
/// - user image:     `{"type":"input_image","image_url":"data:..."}`
/// - assistant text: `{"type":"output_text","text":"..."}`
pub fn parse_content_to_responses_api(content: &str, role: &str) -> Value {
    let is_assistant = role == "assistant";
    let parts = parse_content_to_api(content);
    let Value::Array(arr) = parts else {
        let text_type = if is_assistant { "output_text" } else { "input_text" };
        return serde_json::json!([{ "type": text_type, "text": content }]);
    };
    let converted: Vec<Value> = arr
        .into_iter()
        .map(|part| {
            match part.get("type").and_then(|t| t.as_str()) {
                Some("text") => {
                    let text = part.get("text").and_then(|v| v.as_str()).unwrap_or_default();
                    let text_type = if is_assistant { "output_text" } else { "input_text" };
                    serde_json::json!({ "type": text_type, "text": text })
                }
                Some("image") => {
                    if let Some(source) = part.get("source") {
                        let media_type = source
                            .get("media_type")
                            .and_then(|v| v.as_str())
                            .unwrap_or("image/jpeg");
                        let data = source
                            .get("data")
                            .and_then(|v| v.as_str())
                            .unwrap_or_default();
                        return serde_json::json!({
                            "type": "input_image",
                            "image_url": format!("data:{media_type};base64,{data}")
                        });
                    }
                    part
                }
                _ => part,
            }
        })
        .collect();
    Value::Array(converted)
}

/// Extract the plain text from a content string (strips image parts).
#[allow(dead_code)]
pub fn content_to_text(content: &str) -> String {
    if content.starts_with('[') {
        if let Ok(Value::Array(parts)) = serde_json::from_str::<Value>(content) {
            return parts
                .iter()
                .filter_map(|p| {
                    if p.get("type")?.as_str()? == "text" {
                        p.get("text")?.as_str().map(str::to_string)
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>()
                .join(" ");
        }
    }
    content.to_string()
}

pub async fn get_messages(thread_id: &str, pool: &SqlitePool) -> AppResult<Vec<Message>> {
    let mut messages = sqlx::query_as::<_, Message>(
        r#"
        SELECT id, thread_id, role, model, content, metadata, created_at
        FROM messages
        WHERE thread_id = ?
        ORDER BY created_at DESC
        LIMIT 40
        "#,
    )
    .bind(thread_id)
    .fetch_all(pool)
    .await?;

    messages.reverse();

    Ok(messages)
}

pub async fn save_message(
    thread_id: &str,
    role: &str,
    content: &str,
    model: Option<&str>,
    metadata: Option<&str>,
    pool: &SqlitePool,
) -> AppResult<Message> {
    let id = Uuid::new_v4().to_string().to_uppercase();
    let created_at = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        r#"
        INSERT INTO messages (id, thread_id, role, model, content, metadata, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        "#,
    )
    .bind(&id)
    .bind(thread_id)
    .bind(role)
    .bind(model)
    .bind(content)
    .bind(metadata)
    .bind(&created_at)
    .execute(pool)
    .await?;

    Ok(Message {
        id,
        thread_id: thread_id.to_string(),
        role: role.to_string(),
        model: model.map(str::to_string),
        content: content.to_string(),
        metadata: metadata.map(str::to_string),
        created_at,
    })
}
