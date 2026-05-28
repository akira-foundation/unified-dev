use tauri::{AppHandle, State};

use crate::app::settings;
use crate::app::settings::remote::RemoteSettingsDto;
use crate::app::settings::request::{SyncSettingsDto, UpsertSyncSettingsRequest};
use crate::app::settings::visibility::{UpsertVisibilityPreferencesRequest, VisibilityPreferencesDto};
use crate::app::support::error::{AppError, AppResult};
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

#[tauri::command]
pub async fn touch_org_synced_at(org_id: String, state: State<'_, AppState>, app: AppHandle) -> AppResult<()> {
    settings::touch(org_id, state, app).await
}

#[tauri::command]
pub async fn get_visibility_preferences(scope_type: String, scope_id: String, state: State<'_, AppState>) -> AppResult<VisibilityPreferencesDto> {
    settings::visibility::get(scope_type, scope_id, state).await
}

#[tauri::command]
pub async fn upsert_visibility_preferences(input: UpsertVisibilityPreferencesRequest, state: State<'_, AppState>) -> AppResult<VisibilityPreferencesDto> {
    settings::visibility::upsert(input, state).await
}

#[tauri::command]
pub async fn reset_visibility_preferences(scope_type: String, scope_id: String, state: State<'_, AppState>) -> AppResult<VisibilityPreferencesDto> {
    settings::visibility::reset(scope_type, scope_id, state).await
}

#[tauri::command]
pub async fn get_remote_settings(state: State<'_, AppState>) -> AppResult<RemoteSettingsDto> {
    settings::remote::get(state).await
}

#[tauri::command]
pub async fn set_remote_enabled(enabled: bool, state: State<'_, AppState>, app: AppHandle) -> AppResult<RemoteSettingsDto> {
    if enabled {
        let lifecycle_state = crate::app::license::lifecycle::current_state(&state.db_pool).await?;
        let plan = crate::app::license::get_plan(&state.db_pool).await?;
        let active = matches!(
            lifecycle_state,
            akira_billing::lifecycle::LicenseState::Active
                | akira_billing::lifecycle::LicenseState::Trialing
        );
        if !active || plan != "ultimate" {
            return Err(AppError::FreeTierLimit("remote_requires_ultimate".to_string()));
        }
    }
    let settings = settings::remote::set_enabled(enabled, state, app).await?;
    Ok(settings)
}

#[tauri::command]
pub async fn regenerate_remote_pairing_code(state: State<'_, AppState>) -> AppResult<RemoteSettingsDto> {
    settings::remote::regenerate_pairing_code(state).await
}

#[tauri::command]
pub async fn revoke_remote_device(device_id: String, state: State<'_, AppState>) -> AppResult<RemoteSettingsDto> {
    settings::remote::revoke_device(device_id, state).await
}
