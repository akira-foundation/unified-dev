use serde_json::json;
use sqlx::SqlitePool;

use crate::ai::provider::AiRequest;
use crate::app::chat::message::{content_has_image, parse_content_to_api};

pub fn extract_session_id(val: &serde_json::Value) -> Option<String> {
    val.get("session_id")
        .and_then(|s| s.as_str())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_string())
}

pub fn build_stdin(request: &AiRequest, include_history: bool) -> String {
    let current_has_image = content_has_image(&request.content);
    let mut lines: Vec<String> = Vec::new();

    if include_history {
        for msg in request.history.iter().filter(|m| m.role == "user" || m.role == "assistant") {
            if current_has_image && content_has_image(&msg.content) {
                continue;
            }
            let content = parse_content_to_api(&msg.content);
            lines.push(
                json!({ "type": msg.role, "message": { "role": msg.role, "content": content } })
                    .to_string(),
            );
        }
    }

    let current_content = parse_content_to_api(&request.content);
    lines.push(
        json!({ "type": "user", "message": { "role": "user", "content": current_content } })
            .to_string(),
    );

    lines.join("\n") + "\n"
}

pub async fn read_session(pool: &SqlitePool, thread_id: &str) -> Option<String> {
    sqlx::query_scalar::<_, Option<String>>("SELECT cli_session_id FROM threads WHERE id = ?")
        .bind(thread_id)
        .fetch_optional(pool)
        .await
        .ok()
        .flatten()
        .flatten()
}

pub async fn persist_session(pool: &SqlitePool, thread_id: &str, session_id: &str) {
    let _ = sqlx::query("UPDATE threads SET cli_session_id = ? WHERE id = ?")
        .bind(session_id)
        .bind(thread_id)
        .execute(pool)
        .await;
}

pub async fn clear_session(pool: &SqlitePool, thread_id: &str) {
    let _ = sqlx::query("UPDATE threads SET cli_session_id = NULL WHERE id = ?")
        .bind(thread_id)
        .execute(pool)
        .await;
}

#[cfg(test)]
mod tests {
    use super::extract_session_id;
    use serde_json::json;

    #[test]
    fn extracts_present_session_id() {
        assert_eq!(
            extract_session_id(&json!({ "type": "system", "session_id": "abc-123" })),
            Some("abc-123".to_string())
        );
    }

    #[test]
    fn ignores_empty_session_id() {
        assert_eq!(extract_session_id(&json!({ "session_id": "" })), None);
    }

    #[test]
    fn returns_none_without_session_id() {
        assert_eq!(extract_session_id(&json!({ "type": "assistant" })), None);
    }
}
