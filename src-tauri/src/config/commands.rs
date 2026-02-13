use tauri::State;

use crate::config::models::{AttachRepoInput, CreateOrganizationInput, OrganizationRepoSummary, OrganizationSummary};
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
