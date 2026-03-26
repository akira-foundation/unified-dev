use crate::app::workspaces::local::{add_local_repository as add_logic, AddLocalRepositoryResponse};
use crate::state::AppState;
use crate::support::error::AppResult;

pub async fn add_local_repository(
    local_path: String,
    state: tauri::State<'_, AppState>,
) -> AppResult<AddLocalRepositoryResponse> {
    add_logic(local_path, &state.db_pool).await
}
