use tauri::State;
use crate::error::AppResult;
use crate::state::AppState;
use crate::repositories::add_local_repository::{add_local_repository as add_logic, AddLocalRepositoryResponse};

#[tauri::command]
pub async fn add_local_repository(
    local_path: String,
    state: State<'_, AppState>,
) -> AppResult<AddLocalRepositoryResponse> {
    add_logic(local_path, &state.db_pool).await
}
