use tauri::State;

use crate::app::repos;
use crate::app::support::error::AppResult;
use crate::state::AppState;
use crate::app::repos::AddLocalRepositoryResponse;

#[tauri::command]
pub async fn add_local_repository(local_path: String, state: State<'_, AppState>) -> AppResult<AddLocalRepositoryResponse> {
    repos::add_local(local_path, state).await
}

#[tauri::command]
pub async fn add_remote_repository(url: String, state: State<'_, AppState>) -> AppResult<AddLocalRepositoryResponse> {
    repos::add_remote(url, state).await
}

#[tauri::command]
pub async fn delete_local_repository(repo_id: String, state: State<'_, AppState>) -> AppResult<()> {
    repos::delete_local(repo_id, state).await
}

#[tauri::command]
pub async fn set_local_repository_remote(repo_id: String, remote_url: String, state: State<'_, AppState>) -> AppResult<()> {
    repos::set_remote(repo_id, remote_url, &state.db_pool).await
}

#[tauri::command]
pub async fn link_local_repository_to_organization(repo_id: String, organization_id: String, state: State<'_, AppState>) -> AppResult<()> {
    repos::link_organization(repo_id, organization_id, &state.db_pool).await
}
