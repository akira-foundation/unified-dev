use tauri::State;

use crate::app::repositories;
use crate::support::error::AppResult;
use crate::state::AppState;
use crate::app::workspaces::local::AddLocalRepositoryResponse;

#[tauri::command]
pub async fn add_local_repository(local_path: String, state: State<'_, AppState>) -> AppResult<AddLocalRepositoryResponse> {
    repositories::add_local_repository(local_path, state).await
}

#[tauri::command]
pub async fn add_remote_repository(url: String, state: State<'_, AppState>) -> AppResult<AddLocalRepositoryResponse> {
    repositories::add_remote_repository(url, state).await
}

#[tauri::command]
pub async fn delete_local_repository(repo_id: String, state: State<'_, AppState>) -> AppResult<()> {
    repositories::delete_local_repository(repo_id, state).await
}
