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

#[tauri::command]
pub async fn restore_database(app: AppHandle, source_path: String) -> AppResult<String> {
    let source = std::path::PathBuf::from(source_path);
    let target = crate::app::settings::restore::stage(&app, &source)?;
    let handle = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_millis(800)).await;
        handle.restart();
    });
    Ok(target.to_string_lossy().to_string())
}
