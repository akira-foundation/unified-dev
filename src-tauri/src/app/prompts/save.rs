use tauri::State;

use crate::state::AppState;
use crate::support::error::AppResult;

pub async fn save_prompt(action: String, content: String, state: State<'_, AppState>) -> AppResult<()> {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO prompts (action, content, updated_at) VALUES (?, ?, ?) ON CONFLICT(action) DO UPDATE SET content = excluded.content, updated_at = excluded.updated_at",
    )
    .bind(&action)
    .bind(&content)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;

    Ok(())
}
