use crate::error::AppResult;
use crate::state::AppState;
use std::collections::HashMap;
use tauri::State;

#[tauri::command]
pub async fn get_prompts(state: State<'_, AppState>) -> AppResult<HashMap<String, String>> {
    let rows = sqlx::query_as::<_, (String, String)>(
        "SELECT action, content FROM prompts",
    )
    .fetch_all(&state.db_pool)
    .await?;

    Ok(rows.into_iter().collect())
}

#[tauri::command]
pub async fn save_prompt(
    action: String,
    content: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO prompts (action, content, updated_at) VALUES (?, ?, ?)
         ON CONFLICT(action) DO UPDATE SET content = excluded.content, updated_at = excluded.updated_at",
    )
    .bind(&action)
    .bind(&content)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;

    Ok(())
}

#[tauri::command]
pub async fn reset_prompt(action: String, state: State<'_, AppState>) -> AppResult<()> {
    sqlx::query("DELETE FROM prompts WHERE action = ?")
        .bind(&action)
        .execute(&state.db_pool)
        .await?;

    Ok(())
}
