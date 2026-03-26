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
pub async fn sync_repository_stats(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    orgs::sync_repository_stats(state, organization_id).await
}

#[tauri::command]
pub async fn sync_single_repo_stats(state: State<'_, AppState>, organization_id: String, repo_name: String) -> Result<(), String> {
    orgs::sync_single_repo_stats(state, organization_id, repo_name).await
}

#[tauri::command]
pub async fn list_repo_pull_requests(state: State<'_, AppState>, organization_id: String, repo_name: String) -> Result<Vec<PullRequestDto>, String> {
    orgs::list_repo_pull_requests(state, organization_id, repo_name).await
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
pub async fn submit_pr_review(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, event: PrReviewEvent, body: Option<String>) -> Result<(), String> {
    orgs::submit_pr_review(state, organization_id, repo_name, pr_number, event, body).await
}

#[tauri::command]
pub async fn merge_pr(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, strategy: PrMergeStrategy) -> Result<(), String> {
    orgs::merge_pr(state, organization_id, repo_name, pr_number, strategy).await
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
pub async fn sync_pull_requests(state: State<'_, AppState>, organization_id: String, repo_name: String, owner: Option<String>) -> Result<Vec<PullRequestDto>, String> {
    orgs::sync_pull_requests(state, organization_id, repo_name, owner).await
}
