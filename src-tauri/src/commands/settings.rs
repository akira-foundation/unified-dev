use tauri::State;

use crate::app::settings;
use crate::app::settings::request::{SyncSettingsDto, UpsertSyncSettingsRequest};
use crate::app::support::error::AppResult;
use crate::state::AppState;

#[tauri::command]
pub async fn get_sync_settings(id: String, state: State<'_, AppState>) -> AppResult<SyncSettingsDto> {
    settings::get(id, state).await
}

#[tauri::command]
pub async fn upsert_sync_settings(input: UpsertSyncSettingsRequest, state: State<'_, AppState>) -> AppResult<SyncSettingsDto> {
    settings::upsert(input, state).await
}

#[tauri::command]
pub async fn reset_sync_settings(id: String, state: State<'_, AppState>) -> AppResult<SyncSettingsDto> {
    settings::reset(id, state).await
}
