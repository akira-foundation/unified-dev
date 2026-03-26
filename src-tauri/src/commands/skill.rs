use tauri::State;

use crate::app::skills;
use crate::state::AppState;
use crate::support::error::AppResult;

pub use crate::app::skills::InstalledSkill;

#[tauri::command]
pub async fn sync_skills(state: State<'_, AppState>) -> AppResult<Vec<InstalledSkill>> {
    skills::sync_skills(state).await
}

#[tauri::command]
pub async fn get_skills(state: State<'_, AppState>) -> AppResult<Vec<InstalledSkill>> {
    skills::get_skills(state).await
}

#[tauri::command]
pub async fn set_skill_enabled(id: String, enabled: bool, state: State<'_, AppState>) -> AppResult<()> {
    skills::set_skill_enabled(id, enabled, state).await
}

#[tauri::command]
pub async fn set_skill_icon(id: String, data: Vec<u8>, extension: String, state: State<'_, AppState>) -> AppResult<String> {
    skills::set_skill_icon(id, data, extension, state).await
}

#[tauri::command]
pub async fn install_skill(skill_id: String, repo_url: String, state: State<'_, AppState>) -> AppResult<InstalledSkill> {
    skills::install_skill(skill_id, repo_url, state).await
}

#[tauri::command]
pub async fn uninstall_skill(id: String, state: State<'_, AppState>) -> AppResult<()> {
    skills::uninstall_skill(id, state).await
}

#[tauri::command]
pub fn list_installed_skills() -> Vec<serde_json::Value> {
    skills::list_installed_skills()
}
