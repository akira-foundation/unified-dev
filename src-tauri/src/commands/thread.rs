use tauri::State;

use crate::app::threads;
use crate::app::support::error::AppResult;
use crate::state::AppState;
use crate::app::threads::ThreadConfig;
use crate::providers::dto::{BranchDto, IssueDto, PullRequestDto};

pub use crate::app::threads::RepositoryRow;

#[tauri::command]
pub async fn create_thread(repo_id: String, state: State<'_, AppState>) -> AppResult<ThreadConfig> {
    threads::create(repo_id, state).await
}

#[tauri::command]
pub async fn create_thread_with_title(repo_id: String, title: String, state: State<'_, AppState>) -> AppResult<ThreadConfig> {
    threads::create_with_title(repo_id, title, state).await
}

#[tauri::command]
pub async fn create_thread_from_branch(repo_id: String, title: String, source_commit: String, state: State<'_, AppState>) -> AppResult<ThreadConfig> {
    threads::create_from_branch(repo_id, title, source_commit, state).await
}

#[tauri::command]
pub async fn create_thread_from_pull_request(repo_id: String, title: String, head_sha: String, state: State<'_, AppState>) -> AppResult<ThreadConfig> {
    threads::create_from_pull_request(repo_id, title, head_sha, state).await
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
pub async fn update_repository_settings(
    repo_id: String,
    display_name: Option<String>,
    clear_display_name: bool,
    default_branch: Option<String>,
    default_model_id: Option<String>,
    clear_default_model_id: bool,
    review_model_id: Option<String>,
    clear_review_model_id: bool,
    default_merge_action: Option<String>,
    clear_default_merge_action: bool,
    state: State<'_, AppState>,
) -> AppResult<()> {
    threads::update_repo_settings::update(&repo_id, display_name, clear_display_name, default_branch, default_model_id, clear_default_model_id, review_model_id, clear_review_model_id, default_merge_action, clear_default_merge_action, &state.db_pool).await
}

#[tauri::command]
pub async fn list_repositories(state: State<'_, AppState>) -> AppResult<Vec<RepositoryRow>> {
    threads::list_repos::list(state).await
}

#[tauri::command]
pub async fn get_repo_provider_login(repo_id: String, state: State<'_, AppState>) -> AppResult<Option<String>> {
    threads::source_picker::get_provider_login(repo_id, state).await
}

#[tauri::command]
pub async fn list_thread_source_issues(repo_id: String, state: State<'_, AppState>) -> AppResult<Vec<IssueDto>> {
    threads::source_picker::list_issues(repo_id, state).await
}

#[tauri::command]
pub async fn list_thread_source_pull_requests(repo_id: String, state: State<'_, AppState>) -> AppResult<Vec<PullRequestDto>> {
    threads::source_picker::list_pull_requests(repo_id, state).await
}

#[tauri::command]
pub async fn list_thread_source_branches(repo_id: String, state: State<'_, AppState>) -> AppResult<Vec<BranchDto>> {
    threads::source_picker::list_branches(repo_id, state).await
}
