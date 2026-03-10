use tauri::State;

use serde::Deserialize;

use crate::core::provider::types::{ProviderKind, ProviderOrg, ProviderRepo};
use crate::db::models::{CreateProviderInput, ProviderSummary, TestProviderInput, UpdateProviderAuthInput};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ProviderReposInput {
    pub provider_id: String,
    pub scope: String,
    pub organization_login: Option<String>,
}

#[tauri::command]
pub async fn create_provider(
    state: State<'_, AppState>,
    input: CreateProviderInput,
) -> Result<ProviderSummary, String> {
    state
        .provider_service
        .create_provider(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_providers(state: State<'_, AppState>) -> Result<Vec<ProviderSummary>, String> {
    state
        .provider_service
        .list_providers()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn update_provider_auth(
    state: State<'_, AppState>,
    input: UpdateProviderAuthInput,
) -> Result<(), String> {
    state
        .provider_service
        .update_provider_auth(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn delete_provider(state: State<'_, AppState>, provider_id: String) -> Result<(), String> {
    state
        .provider_service
        .delete_provider(&provider_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn test_provider_connection(
    state: State<'_, AppState>,
    input: TestProviderInput,
) -> Result<(), String> {
    let kind = ProviderKind::from_str(&input.kind);
    let provider = state
        .provider_factory
        .create(&kind, input.auth)
        .map_err(|error| error.to_string())?;

    provider
        .validate_auth()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_provider_organizations(
    state: State<'_, AppState>,
    provider_id: String,
) -> Result<Vec<ProviderOrg>, String> {
    let credentials = state
        .provider_service
        .credentials(&provider_id)
        .await
        .map_err(|error| error.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .map_err(|error| error.to_string())?;

    provider
        .list_organizations()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_provider_repositories(
    state: State<'_, AppState>,
    input: ProviderReposInput,
) -> Result<Vec<ProviderRepo>, String> {
    let credentials = state
        .provider_service
        .credentials(&input.provider_id)
        .await
        .map_err(|error| error.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .map_err(|error| error.to_string())?;

    match input.scope.as_str() {
        "personal" => provider
            .list_repositories()
            .await
            .map_err(|error| error.to_string()),
        "organization" => {
            let login = input
                .organization_login
                .ok_or_else(|| "organization_login is required".to_string())?;
            provider
                .list_organization_repositories(&login)
                .await
                .map_err(|error| error.to_string())
        }
        _ => Err("invalid scope".to_string()),
    }
}
