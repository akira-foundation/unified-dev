use tauri::State;

use crate::error::AppResult;
use crate::state::AppState;
use crate::workspaces::delete::delete_local_repository as delete_logic;
use crate::workspaces::local::{add_local_repository as add_logic, AddLocalRepositoryResponse};
use crate::workspaces::remote::add_remote_repository as add_remote_logic;

#[tauri::command]
pub async fn add_local_repository(
    local_path: String,
    state: State<'_, AppState>,
) -> AppResult<AddLocalRepositoryResponse> {
    add_logic(local_path, &state.db_pool).await
}

#[tauri::command]
pub async fn add_remote_repository(
    url: String,
    state: State<'_, AppState>,
) -> AppResult<AddLocalRepositoryResponse> {
    add_remote_logic(url, &state.db_pool).await
}

#[tauri::command]
pub async fn delete_local_repository(
    repo_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    delete_logic(repo_id, &state.db_pool).await
}
