use crate::app::workspaces::delete::delete_local_repository as delete_logic;
use crate::state::AppState;
use crate::support::error::AppResult;

pub async fn delete_local_repository(
    repo_id: String,
    state: tauri::State<'_, AppState>,
) -> AppResult<()> {
    delete_logic(repo_id, &state.db_pool).await
}
