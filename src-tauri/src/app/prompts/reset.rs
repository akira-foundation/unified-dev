use tauri::State;

use crate::state::AppState;
use crate::support::error::AppResult;

pub async fn reset_prompt(action: String, state: State<'_, AppState>) -> AppResult<()> {
    sqlx::query("DELETE FROM prompts WHERE action = ?")
        .bind(&action)
        .execute(&state.db_pool)
        .await?;

    Ok(())
}
