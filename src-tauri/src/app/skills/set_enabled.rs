use tauri::State;

use crate::state::AppState;
use crate::support::error::AppResult;

pub async fn set_skill_enabled(id: String, enabled: bool, state: State<'_, AppState>) -> AppResult<()> {
    sqlx::query("UPDATE skills SET enabled = ? WHERE id = ?")
        .bind(enabled)
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}
