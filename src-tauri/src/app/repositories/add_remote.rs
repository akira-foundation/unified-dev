use crate::app::workspaces::local::AddLocalRepositoryResponse;
use crate::app::workspaces::remote::add_remote_repository as add_remote_logic;
use crate::state::AppState;
use crate::support::error::AppResult;

pub async fn add_remote_repository(
    url: String,
    state: tauri::State<'_, AppState>,
) -> AppResult<AddLocalRepositoryResponse> {
    add_remote_logic(url, &state.db_pool).await
}
