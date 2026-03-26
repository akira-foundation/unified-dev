use tauri::State;

use crate::app::issues;
use crate::app::issues::request::{CreateIssueRequest, UpdateIssueRequest};
use crate::providers::dto::IssueDto;
use crate::state::AppState;

#[tauri::command]
pub async fn sync_issues(
    state: State<'_, AppState>,
    org_id: String,
    owner: String,
    repo_name: String,
    state_filter: Option<String>,
) -> Result<Vec<IssueDto>, String> {
    issues::sync(state, org_id, owner, repo_name, state_filter).await
}

#[tauri::command]
pub async fn list_issues(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
) -> Result<Vec<IssueDto>, String> {
    issues::list(state, org_id, repo_name).await
}

#[tauri::command]
pub async fn get_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
) -> Result<Option<IssueDto>, String> {
    issues::get(state, org_id, repo_name, number).await
}

#[tauri::command]
pub async fn create_issue(
    state: State<'_, AppState>,
    input: CreateIssueRequest,
) -> Result<IssueDto, String> {
    issues::create(state, input).await
}

#[tauri::command]
pub async fn update_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    input: UpdateIssueRequest,
) -> Result<IssueDto, String> {
    issues::update(state, org_id, repo_name, number, input).await
}

#[tauri::command]
pub async fn close_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    reason: Option<String>,
) -> Result<(), String> {
    issues::close(state, org_id, repo_name, number, reason).await
}

#[tauri::command]
pub async fn delete_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
) -> Result<(), String> {
    issues::delete(state, org_id, repo_name, number).await
}
