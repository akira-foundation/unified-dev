use tauri::{AppHandle, State};

use crate::app::skills;
use crate::state::AppState;
use crate::app::support::error::AppResult;

pub use crate::app::skills::InstalledSkill;

#[tauri::command]
pub async fn sync_skills(
    workspace_path: Option<String>,
    app_handle: AppHandle,
    state: State<'_, AppState>,
) -> AppResult<Vec<InstalledSkill>> {
    skills::sync(app_handle, workspace_path, state).await
}

#[tauri::command]
pub async fn get_skills(state: State<'_, AppState>) -> AppResult<Vec<InstalledSkill>> {
    skills::get(state).await
}

#[tauri::command]
pub async fn set_skill_enabled(
    id: String,
    enabled: bool,
    state: State<'_, AppState>,
) -> AppResult<()> {
    skills::set_enabled(id, enabled, state).await
}

#[tauri::command]
pub async fn set_skill_icon(
    id: String,
    data: Vec<u8>,
    extension: String,
    app_handle: AppHandle,
    state: State<'_, AppState>,
) -> AppResult<String> {
    skills::set_icon(id, data, extension, app_handle, state).await
}

#[tauri::command]
pub async fn install_skill(
    skill_id: String,
    repo_url: String,
    app_handle: AppHandle,
    state: State<'_, AppState>,
) -> AppResult<InstalledSkill> {
    skills::install(skill_id, repo_url, app_handle, state).await
}

#[tauri::command]
pub async fn uninstall_skill(
    id: String,
    app_handle: AppHandle,
    state: State<'_, AppState>,
) -> AppResult<()> {
    skills::uninstall(id, app_handle, state).await
}

#[tauri::command]
pub fn list_installed_skills() -> Vec<serde_json::Value> {
    skills::list_installed()
}
