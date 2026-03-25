use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;
use uuid::Uuid;

use crate::error::AppResult;

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

    // Reverse so the slice is oldest-first for the model context window.
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
