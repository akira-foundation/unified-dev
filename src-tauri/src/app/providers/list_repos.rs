use akira_billing::types::GithubInstallationTokenPayload;
use serde::Deserialize;
use tauri::State;

use crate::app::concerns::VcsProvider;
use crate::providers::dto::ProviderRepo;
use crate::providers::drivers::github::client::GitHubDriver;
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct ProviderReposInput {
    pub provider_id: String,
    pub scope: String,
    pub organization_login: Option<String>,
}

async fn fetch_installation_token(state: &State<'_, AppState>, installation_id: Option<u64>) -> Result<String, String> {
    let billing = state.billing.read().await;
    let response = billing
        .inner()
        .github_installation_token(GithubInstallationTokenPayload { installation_id })
        .await
        .map_err(|error| format!("installation token request failed: {error}"))?;
    Ok(response.token)
}

async fn resolve_installation_id_for_login(state: &State<'_, AppState>, login: &str) -> Result<u64, String> {
    let billing = state.billing.read().await;
    let response = billing
        .inner()
        .me_github_installations()
        .await
        .map_err(|error| format!("list installations failed: {error}"))?;
    response
        .installations
        .iter()
        .find(|installation| installation.account_login == login)
        .map(|installation| installation.id)
        .ok_or_else(|| format!("no installation found for {login}"))
}

pub async fn list_repos(state: State<'_, AppState>, input: ProviderReposInput) -> Result<Vec<ProviderRepo>, String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &input.provider_id)
        .await
        .map_err(|error| error.to_string())?;

    if credentials.kind == ProviderKind::GitHub {
        if let ProviderAuth::GitHubApp { installation_token, .. } = credentials.auth.clone() {
            let target_login = match input.scope.as_str() {
                "personal" => None,
                "organization" => input.organization_login.clone(),
                _ => return Err("invalid scope".to_string()),
            };

            let token = if let Some(ref login) = target_login {
                let org_installation_id = resolve_installation_id_for_login(&state, login).await?;
                fetch_installation_token(&state, Some(org_installation_id)).await?
            } else {
                installation_token
            };

            let provider = GitHubDriver::new(token).map_err(|error| error.to_string())?;

            return match input.scope.as_str() {
                "personal" => provider.list_repositories().await.map_err(|error| error.to_string()),
                "organization" => provider
                    .list_organization_repositories(target_login.as_deref().unwrap_or_default())
                    .await
                    .map_err(|error| error.to_string()),
                _ => Err("invalid scope".to_string()),
            };
        }
    }

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
