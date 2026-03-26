use tauri::State;
use serde::Deserialize;

use crate::providers::dto::ProviderRepo;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ProviderReposInput {
    pub provider_id: String,
    pub scope: String,
    pub organization_login: Option<String>,
}

pub async fn list_repos(state: State<'_, AppState>, input: ProviderReposInput) -> Result<Vec<ProviderRepo>, String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &input.provider_id)
        .await
        .map_err(|error| error.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|error| error.to_string())?;

    match input.scope.as_str() {
        "personal" => provider.list_repositories().await.map_err(|error| error.to_string()),
        "organization" => {
            let login = input.organization_login.ok_or_else(|| "organization_login is required".to_string())?;
            provider
                .list_organization_repositories(&login)
                .await
                .map_err(|error| error.to_string())
        }
        _ => Err("invalid scope".to_string()),
    }
}
