pub mod agents;
pub mod create;
pub mod delete;
pub mod list_repos;
pub mod rename;
pub mod set_pr_url;
pub mod source_picker;
pub mod update_repo_settings;

use crate::state::AppState;
use crate::app::support::error::AppResult;

pub use create::{create as create_logic, create_from_branch as create_from_branch_logic, create_from_pull_request as create_from_pull_request_logic, create_with_paths, create_with_title as create_with_title_logic, ThreadConfig};
pub use delete::delete as delete_logic;
pub use list_repos::{RepositoryRow, ThreadRow};
pub use rename::rename as rename_logic;
pub use set_pr_url::set as set_pr_url_logic;

pub async fn create(repo_id: String, state: tauri::State<'_, AppState>) -> AppResult<ThreadConfig> {
    create_logic(repo_id, &state.db_pool).await
}

pub async fn create_with_title(repo_id: String, title: String, state: tauri::State<'_, AppState>) -> AppResult<ThreadConfig> {
    create_with_title_logic(repo_id, title, &state.db_pool).await
}

pub async fn create_from_branch(repo_id: String, title: String, source_commit: String, state: tauri::State<'_, AppState>) -> AppResult<ThreadConfig> {
    create_from_branch_logic(repo_id, title, source_commit, &state.db_pool).await
}

pub async fn create_from_pull_request(repo_id: String, title: String, head_sha: String, state: tauri::State<'_, AppState>) -> AppResult<ThreadConfig> {
    create_from_pull_request_logic(repo_id, title, head_sha, &state.db_pool).await
}

pub async fn delete(thread_id: String, state: tauri::State<'_, AppState>) -> AppResult<()> {
    delete_logic(thread_id, &state.db_pool).await
}

pub async fn rename(thread_id: String, new_name: String, state: tauri::State<'_, AppState>) -> AppResult<ThreadRow> {
    rename_logic(&thread_id, &new_name, &state.db_pool).await
}

pub async fn set_pr_url(
    thread_id: String,
    pr_url: String,
    pr_is_draft: bool,
    state: tauri::State<'_, AppState>,
) -> AppResult<()> {
    set_pr_url_logic(&thread_id, &pr_url, pr_is_draft, &state.db_pool).await
}
