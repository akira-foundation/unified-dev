use tauri::State;

use crate::app::issues;
use crate::db::inputs::{CreateIssueInput, UpdateIssueInput};
use crate::providers::types::IssueDto;
use crate::state::AppState;

#[tauri::command]
pub async fn sync_issues(
    state: State<'_, AppState>,
    org_id: String,
    owner: String,
    repo_name: String,
    state_filter: Option<String>,
) -> Result<Vec<IssueDto>, String> {
    issues::sync_issues(state, org_id, owner, repo_name, state_filter).await
}

#[tauri::command]
pub async fn list_issues(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
) -> Result<Vec<IssueDto>, String> {
    issues::list_issues(state, org_id, repo_name).await
}

#[tauri::command]
pub async fn get_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
) -> Result<Option<IssueDto>, String> {
    issues::get_issue(state, org_id, repo_name, number).await
}

#[tauri::command]
pub async fn create_issue(
    state: State<'_, AppState>,
    input: CreateIssueInput,
) -> Result<IssueDto, String> {
    issues::create_issue(state, input).await
}

#[tauri::command]
pub async fn update_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    input: UpdateIssueInput,
) -> Result<IssueDto, String> {
    issues::update_issue(state, org_id, repo_name, number, input).await
}

#[tauri::command]
pub async fn close_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    reason: Option<String>,
) -> Result<(), String> {
    issues::close_issue(state, org_id, repo_name, number, reason).await
}

#[tauri::command]
pub async fn delete_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
) -> Result<(), String> {
    issues::delete_issue(state, org_id, repo_name, number).await
}
