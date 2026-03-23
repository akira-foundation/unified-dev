use tauri::State;

use crate::db::models::{
    CreateOrganizationInput, OrganizationRepoSummary, OrganizationRepoWithOrg, OrganizationSummary, SelectedRepositoryInput,
};
use crate::state::AppState;

#[tauri::command]
pub async fn create_organization(
    state: State<'_, AppState>,
    input: CreateOrganizationInput,
) -> Result<OrganizationSummary, String> {
    state
        .organization_service
        .create_organization(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_organizations(state: State<'_, AppState>) -> Result<Vec<OrganizationSummary>, String> {
    state
        .organization_service
        .list_organizations()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_organizations_by_provider(
    state: State<'_, AppState>,
    provider_id: String,
) -> Result<Vec<OrganizationSummary>, String> {
    state
        .organization_service
        .list_by_provider(&provider_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn delete_organization(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    state
        .organization_service
        .delete_organization(&organization_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn save_selected_repositories(
    state: State<'_, AppState>,
    organization_id: String,
    repo_list: Vec<SelectedRepositoryInput>,
) -> Result<(), String> {
    state
        .organization_repo_service
        .save_selected_repositories(&organization_id, repo_list)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_selected_repositories(
    state: State<'_, AppState>,
    organization_id: String,
) -> Result<Vec<OrganizationRepoSummary>, String> {
    state
        .organization_repo_service
        .list_selected_repositories(&organization_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_all_selected_repositories(
    state: State<'_, AppState>,
) -> Result<Vec<OrganizationRepoWithOrg>, String> {
    state
        .organization_repo_service
        .list_all_selected_repositories()
        .await
        .map_err(|error| error.to_string())
}
