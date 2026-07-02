use tauri::State;

use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn reset(action: String, state: State<'_, AppState>) -> AppResult<()> {
    sqlx::query("DELETE FROM prompts WHERE action = ?")
        .bind(&action)
        .execute(&state.pool().await?)
        .await?;

    Ok(())
}
