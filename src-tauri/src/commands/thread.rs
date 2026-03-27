use tauri::State;

use crate::app::threads;
use crate::app::support::error::AppResult;
use crate::state::AppState;
use crate::app::threads::ThreadConfig;

pub use crate::app::threads::RepositoryRow;

#[tauri::command]
pub async fn create_thread(repo_id: String, state: State<'_, AppState>) -> AppResult<ThreadConfig> {
    threads::create(repo_id, state).await
}

#[tauri::command]
pub async fn delete_thread(thread_id: String, state: State<'_, AppState>) -> AppResult<()> {
    threads::delete(thread_id, state).await
}

#[tauri::command]
pub async fn rename_thread(thread_id: String, new_name: String, state: State<'_, AppState>) -> AppResult<crate::app::threads::ThreadRow> {
    threads::rename(thread_id, new_name, state).await
}

#[tauri::command]
pub async fn set_thread_pr_url(thread_id: String, pr_url: String, pr_is_draft: bool, state: State<'_, AppState>) -> AppResult<()> {
    threads::set_pr_url(thread_id, pr_url, pr_is_draft, state).await
}

#[tauri::command]
pub async fn list_repositories(state: State<'_, AppState>) -> AppResult<Vec<RepositoryRow>> {
    threads::list_repos::list(state).await
}
