use tauri::{AppHandle, State};

use crate::app::settings::update::{self, UpdateSettings};
use crate::app::support::error::AppResult;
use crate::state::AppState;

#[tauri::command]
pub async fn get_update_settings(state: State<'_, AppState>) -> AppResult<UpdateSettings> {
    update::get(&state.db_pool).await
}

#[tauri::command]
pub async fn set_update_settings(
    state: State<'_, AppState>,
    settings: UpdateSettings,
) -> AppResult<UpdateSettings> {
    update::set(&state.db_pool, settings).await
}

#[tauri::command]
pub async fn backup_database_now(
    state: State<'_, AppState>,
    app: AppHandle,
    target_version: Option<String>,
) -> AppResult<Option<String>> {
    let db_path = crate::database::database_path(&app)?;
    let dest =
        update::perform_backup(&state.db_pool, &db_path, target_version.as_deref().unwrap_or("manual")).await?;
    Ok(dest.map(|p| p.to_string_lossy().to_string()))
}
