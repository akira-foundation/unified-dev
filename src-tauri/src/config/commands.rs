use tauri::State;

use crate::config::models::{
    AttachRepoInput, CreateOrganizationInput, OrganizationRepoSummary, OrganizationSummary,
    SelectedRepositoryInput,
};
use crate::core::provider::types::ProviderRepo;
use crate::state::AppState;

#[tauri::command]
pub async fn list_organizations(state: State<'_, AppState>) -> Result<Vec<OrganizationSummary>, String> {
    state
        .organization_service
        .list_organizations()
        .await
        .map_err(|error| error.to_string())
}

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
pub async fn delete_organization(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    state
        .organization_service
        .delete_organization(&organization_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn attach_repo_to_organization(
    state: State<'_, AppState>,
    input: AttachRepoInput,
) -> Result<OrganizationRepoSummary, String> {
    state
        .organization_service
        .attach_repo(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_organization_repos(
    state: State<'_, AppState>,
    organization_id: String,
) -> Result<Vec<OrganizationRepoSummary>, String> {
    state
        .organization_service
        .list_repos(&organization_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn fetch_organization_repositories(
    state: State<'_, AppState>,
    organization_id: String,
) -> Result<Vec<ProviderRepo>, String> {
    let credentials = state
        .organization_service
        .organization_credentials(&organization_id)
        .await
        .map_err(|error| error.to_string())?;

    let provider = state
        .provider_registry
        .create(&credentials.provider_id, credentials.auth)
        .map_err(|error| error.to_string())?;

    provider
        .list_repositories()
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
        .organization_service
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
        .organization_service
        .list_selected_repos(&organization_id)
        .await
        .map_err(|error| error.to_string())
}
