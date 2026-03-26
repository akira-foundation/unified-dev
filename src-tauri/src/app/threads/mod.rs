pub mod agents;
pub mod create;
pub mod delete;
pub mod list_repositories;
pub mod set_pr_url;

use crate::state::AppState;
use crate::support::error::AppResult;

pub use create::{create as create_logic, create_with_paths, ThreadConfig};
pub use delete::delete as delete_logic;
pub use list_repositories::RepositoryRow;
pub use set_pr_url::set as set_pr_url_logic;

pub async fn create(repo_id: String, state: tauri::State<'_, AppState>) -> AppResult<ThreadConfig> {
    create_logic(repo_id, &state.db_pool).await
}

pub async fn delete(thread_id: String, state: tauri::State<'_, AppState>) -> AppResult<()> {
    delete_logic(thread_id, &state.db_pool).await
}

pub async fn set_pr_url(
    thread_id: String,
    pr_url: String,
    pr_is_draft: bool,
    state: tauri::State<'_, AppState>,
) -> AppResult<()> {
    set_pr_url_logic(&thread_id, &pr_url, pr_is_draft, &state.db_pool).await
}
