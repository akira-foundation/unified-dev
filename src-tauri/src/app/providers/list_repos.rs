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
    if let Some(id) = installation_id {
        return crate::app::orgs::resolve_provider::get_cached_or_mint_token(state.inner(), id).await;
    }

    let billing = state.billing.read().await;
    let response = billing
        .inner()
        .github_installation_token(GithubInstallationTokenPayload { installation_id })
        .await
        .map_err(|error| format!("installation token request failed: {error}"))?;
    Ok(response.token)
}

async fn resolve_installation_id_for_login(state: &State<'_, AppState>, provider_id: &str, login: &str) -> Result<u64, String> {
    let credentials = crate::app::providers::credentials::credentials(state, provider_id)
        .await
        .map_err(|error| error.to_string())?;

    if let ProviderAuth::GitHubApp { oauth_access_token, .. } = credentials.auth {
        let installations = crate::app::orgs::resolve_provider::get_cached_or_fetch_installations(&oauth_access_token).await?;
        installations
            .iter()
            .find(|installation| installation.account.login == login)
            .map(|installation| installation.id)
            .ok_or_else(|| format!("no installation found for {login}"))
    } else {
        Err("not a github app provider".to_string())
    }
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

            let (token, org_installation_id) = if let Some(ref login) = target_login {
                let id = resolve_installation_id_for_login(&state, &input.provider_id, login).await?;
                (fetch_installation_token(&state, Some(id)).await?, Some(id))
            } else {
                (installation_token, None)
            };

            let mut provider = GitHubDriver::new(token).map_err(|error| error.to_string())?;
            if let Some(id) = org_installation_id {
                provider = provider.with_auth_failure_hook(std::sync::Arc::new(move || {
                    crate::app::orgs::resolve_provider::invalidate_installation_token(id)
                }));
            }

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
