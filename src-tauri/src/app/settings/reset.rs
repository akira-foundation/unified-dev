use tauri::State;

use crate::app::settings::get::get;
use crate::app::support::error::AppResult;
use crate::app::settings::request::SyncSettingsDto;
use crate::state::AppState;

pub async fn reset(id: String, state: State<'_, AppState>) -> AppResult<SyncSettingsDto> {
    sqlx::query("DELETE FROM sync_settings WHERE id = ?")
        .bind(&id)
        .execute(&state.db_pool)
        .await?;

    get(id, state).await
}
