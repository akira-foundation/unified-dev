use tauri::State;

use crate::app::issues;
use crate::app::issues::request::{CreateIssueRequest, UpdateIssueRequest};
use crate::app::repos::types::AddLocalRepositoryResponse;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

#[tauri::command]
pub async fn sync_issues(
    state: State<'_, AppState>,
    org_id: String,
    owner: String,
    repo_name: String,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<IssueDto>, String> {
    issues::sync(state, org_id, owner, repo_name, scope, current_login).await
}

#[tauri::command]
pub async fn list_issues(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<IssueDto>, String> {
    issues::list(state, org_id, repo_name, scope, current_login).await
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

#[tauri::command]
pub async fn delegate_issue_to_agent(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    issue_title: String,
) -> Result<AddLocalRepositoryResponse, String> {
    issues::delegate(&state, org_id, repo_name, issue_title)
        .await
        .map_err(|e| e.to_string())
}
