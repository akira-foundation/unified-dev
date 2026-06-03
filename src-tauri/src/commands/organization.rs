use tauri::State;

use crate::app::orgs;
use crate::app::orgs::request::{CreateOrgRequest, SelectRepoRequest, UpdateOrgRequest};
use crate::database::records::{OrganizationRepoSummary, OrganizationRepoWithOrg, OrganizationSummary};
use crate::providers::dto::{BranchDto, CiCheckDto, PrCommentDto, PrFileDto, PullRequestDto};
use crate::providers::enums::{PrMergeStrategy, PrReviewEvent};
use crate::state::AppState;

#[tauri::command]
pub async fn create_organization(state: State<'_, AppState>, input: CreateOrgRequest) -> Result<OrganizationSummary, String> {
    orgs::create_organization(state, input).await
}

#[tauri::command]
pub async fn list_organizations(state: State<'_, AppState>) -> Result<Vec<OrganizationSummary>, String> {
    orgs::list_organizations(state).await
}

#[tauri::command]
pub async fn list_organizations_by_provider(state: State<'_, AppState>, provider_id: String) -> Result<Vec<OrganizationSummary>, String> {
    orgs::list_organizations_by_provider(state, provider_id).await
}

#[tauri::command]
pub async fn update_organization(state: State<'_, AppState>, input: UpdateOrgRequest) -> Result<OrganizationSummary, String> {
    orgs::update_organization(state, input).await
}

#[tauri::command]
pub async fn delete_organization(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    orgs::delete_organization(state, organization_id).await
}

#[tauri::command]
pub async fn save_selected_repositories(state: State<'_, AppState>, organization_id: String, repo_list: Vec<SelectRepoRequest>) -> Result<(), String> {
    orgs::save_selected_repositories(state, organization_id, repo_list).await
}

#[tauri::command]
pub async fn list_selected_repositories(state: State<'_, AppState>, organization_id: String) -> Result<Vec<OrganizationRepoSummary>, String> {
    orgs::list_selected_repositories(state, organization_id).await
}

#[tauri::command]
pub async fn list_all_selected_repositories(state: State<'_, AppState>) -> Result<Vec<OrganizationRepoWithOrg>, String> {
    orgs::list_all_selected_repositories(state).await
}

#[tauri::command]
pub async fn sync_repository_stats(state: State<'_, AppState>, app: tauri::AppHandle, organization_id: String) -> Result<(), String> {
    orgs::sync_repository_stats(state.clone(), organization_id.clone()).await?;
    crate::app::settings::touch::touch(organization_id, state, app).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn sync_single_repo_stats(state: State<'_, AppState>, app: tauri::AppHandle, organization_id: String, repo_name: String) -> Result<(), String> {
    orgs::sync_single_repo_stats(state.clone(), organization_id.clone(), repo_name).await?;
    crate::app::settings::touch::touch(organization_id, state, app).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn list_repo_pull_requests(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<PullRequestDto>, String> {
    orgs::list_repo_pull_requests(state, organization_id, repo_name, scope, current_login).await
}

#[tauri::command]
pub async fn get_pr_comments(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64) -> Result<Vec<PrCommentDto>, String> {
    orgs::get_pr_comments(state, organization_id, repo_name, pr_number).await
}

#[tauri::command]
pub async fn post_pr_comment(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, body: String) -> Result<PrCommentDto, String> {
    orgs::post_pr_comment(state, organization_id, repo_name, pr_number, body).await
}

#[tauri::command]
pub async fn delete_pr_comment(state: State<'_, AppState>, organization_id: String, repo_name: String, comment_id: String) -> Result<(), String> {
    orgs::delete_pr_comment(state, organization_id, repo_name, comment_id).await
}

#[tauri::command]
pub async fn update_pr_body(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, body: String) -> Result<(), String> {
    orgs::update_pr_body(state, organization_id, repo_name, pr_number, body).await
}

#[tauri::command]
pub async fn submit_pr_review(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, event: PrReviewEvent, body: Option<String>) -> Result<(), String> {
    orgs::submit_pr_review(state, organization_id, repo_name, pr_number, event, body).await
}

#[tauri::command]
pub async fn merge_pr(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, strategy: PrMergeStrategy) -> Result<(), String> {
    orgs::merge_pr(state, organization_id, repo_name, pr_number, strategy).await
}

#[tauri::command]
pub async fn mark_pr_ready_for_review(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64) -> Result<(), String> {
    orgs::mark_pr_ready(state, organization_id, repo_name, pr_number).await
}

#[tauri::command]
pub async fn close_pr(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, comment: Option<String>) -> Result<(), String> {
    orgs::close_pr(state, organization_id, repo_name, pr_number, comment).await
}

#[tauri::command]
pub async fn reopen_pr(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64) -> Result<(), String> {
    orgs::reopen_pr(state, organization_id, repo_name, pr_number).await
}

#[tauri::command]
pub async fn list_pr_repo_labels(state: State<'_, AppState>, organization_id: String, repo_name: String) -> Result<Vec<orgs::RepoLabelDto>, String> {
    orgs::list_pr_repo_labels(state, organization_id, repo_name).await
}

#[tauri::command]
pub async fn set_pr_labels(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, labels: Vec<String>) -> Result<Vec<String>, String> {
    orgs::set_pr_labels(state, organization_id, repo_name, pr_number, labels).await
}

#[tauri::command]
pub async fn create_pr_repo_label(state: State<'_, AppState>, organization_id: String, repo_name: String, name: String, color: Option<String>, description: Option<String>) -> Result<orgs::RepoLabelDto, String> {
    orgs::create_pr_repo_label(state, organization_id, repo_name, name, color, description).await
}

#[tauri::command]
pub async fn get_pr_files(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64) -> Result<Vec<PrFileDto>, String> {
    orgs::get_pr_files(state, organization_id, repo_name, pr_number).await
}

#[tauri::command]
pub async fn get_pr_checks(state: State<'_, AppState>, organization_id: String, repo_name: String, head_sha: String) -> Result<Vec<CiCheckDto>, String> {
    orgs::get_pr_checks(state, organization_id, repo_name, head_sha).await
}

#[tauri::command]
pub async fn get_job_logs(state: State<'_, AppState>, organization_id: String, repo_name: String, job_id: u64) -> Result<String, String> {
    orgs::get_job_logs(state, organization_id, repo_name, job_id).await
}

#[tauri::command]
pub async fn list_repo_branches(state: State<'_, AppState>, organization_id: String, repo_name: String) -> Result<Vec<BranchDto>, String> {
    orgs::list_repo_branches(state, organization_id, repo_name).await
}

#[tauri::command]
pub async fn create_repo_branch(state: State<'_, AppState>, organization_id: String, repo_name: String, branch_name: String, from_sha: String) -> Result<BranchDto, String> {
    orgs::create_repo_branch(state, organization_id, repo_name, branch_name, from_sha).await
}

#[tauri::command]
pub async fn delete_repo_branch(state: State<'_, AppState>, organization_id: String, repo_name: String, branch_name: String) -> Result<(), String> {
    orgs::delete_repo_branch(state, organization_id, repo_name, branch_name).await
}

#[tauri::command]
pub async fn sync_pull_requests(
    state: State<'_, AppState>,
    app: tauri::AppHandle,
    organization_id: String,
    repo_name: String,
    owner: Option<String>,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<PullRequestDto>, String> {
    let prs = orgs::sync_pull_requests(state.clone(), organization_id.clone(), repo_name, owner, scope, current_login).await?;
    crate::app::settings::touch::touch(organization_id, state, app).await.map_err(|e| e.to_string())?;
    Ok(prs)
}
