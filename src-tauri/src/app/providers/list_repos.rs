use tauri::State;
use serde::Deserialize;

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

async fn fetch_github_installation_token(oauth_access_token: &str, target_login: &str) -> Result<String, String> {
    #[derive(serde::Deserialize)]
    struct InstallationTokenResponse {
        token: String,
    }

    let api_url = env!("AKIRA_API_URL");

    let client = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .map_err(|e| e.to_string())?;

    let response = client
        .post(format!("{api_url}/github/installation-token"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({
            "access_token": oauth_access_token,
            "target_login": target_login,
        }))
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.map_err(|e| e.to_string())?;
        return Err(format!("installation token request failed: {status} — {body}"));
    }

    let result: InstallationTokenResponse = response.json().await.map_err(|e| e.to_string())?;

    Ok(result.token)
}

pub async fn list_repos(state: State<'_, AppState>, input: ProviderReposInput) -> Result<Vec<ProviderRepo>, String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &input.provider_id)
        .await
        .map_err(|error| error.to_string())?;

    if credentials.kind == ProviderKind::GitHub {
        if let ProviderAuth::GitHubApp { oauth_access_token, installation_token, .. } = credentials.auth.clone() {
            let target_login = match input.scope.as_str() {
                "personal" => None,
                "organization" => input.organization_login.clone(),
                _ => return Err("invalid scope".to_string()),
            };

            let token = if let Some(login) = target_login.as_deref() {
                fetch_github_installation_token(&oauth_access_token, login).await?
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
