use tauri::State;

use serde::Deserialize;

use crate::app::providers;
use crate::app::providers::request::{CreateProviderRequest, TestProviderConnectionRequest, UpdateProviderAuthRequest};
use crate::app::providers::{RateLimitDto};
use crate::database::records::ProviderSummary;
use crate::providers::dto::{ProviderOrg, ProviderRepo};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ProviderReposInput {
    pub provider_id: String,
    pub scope: String,
    pub organization_login: Option<String>,
}

#[tauri::command]
pub async fn create_provider(state: State<'_, AppState>, input: CreateProviderRequest) -> Result<ProviderSummary, String> {
    providers::create(state, input).await
}

#[tauri::command]
pub async fn list_providers(state: State<'_, AppState>) -> Result<Vec<ProviderSummary>, String> {
    providers::list(state).await
}

#[tauri::command]
pub async fn update_provider_auth(state: State<'_, AppState>, input: UpdateProviderAuthRequest) -> Result<(), String> {
    providers::update_auth(state, input).await
}

#[tauri::command]
pub async fn delete_provider(state: State<'_, AppState>, provider_id: String, keep_organizations: bool) -> Result<(), String> {
    providers::delete(state, provider_id, keep_organizations).await
}

#[tauri::command]
pub async fn test_provider_connection(state: State<'_, AppState>, input: TestProviderConnectionRequest) -> Result<(), String> {
    providers::test_connection(state, input).await
}

#[tauri::command]
pub async fn connect_github(state: State<'_, AppState>, app: tauri::AppHandle) -> Result<ProviderSummary, String> {
    providers::connect_github(state, app).await
}

#[tauri::command]
pub async fn install_github_app(state: State<'_, AppState>, app: tauri::AppHandle) -> Result<(), String> {
    providers::install_github_app(state, app).await
}

#[tauri::command]
pub async fn uninstall_github_app(state: State<'_, AppState>, provider_id: String, target_login: String) -> Result<(), String> {
    providers::uninstall_github_app(state, provider_id, target_login).await
}

#[tauri::command]
pub async fn list_provider_organizations(state: State<'_, AppState>, provider_id: String) -> Result<Vec<ProviderOrg>, String> {
    providers::list_organizations(state, provider_id).await
}

#[tauri::command]
pub async fn list_provider_repositories(state: State<'_, AppState>, input: ProviderReposInput) -> Result<Vec<ProviderRepo>, String> {
    providers::list_repos(
        state,
        providers::ProviderReposInput {
            provider_id: input.provider_id,
            scope: input.scope,
            organization_login: input.organization_login,
        },
    )
    .await
}

#[tauri::command]
pub async fn get_rate_limit(state: State<'_, AppState>) -> Result<Vec<RateLimitDto>, String> {
    providers::get_rate_limit(state).await
}
