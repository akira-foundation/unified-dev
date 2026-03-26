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
