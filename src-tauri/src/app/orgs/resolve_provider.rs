use std::sync::Arc;

use crate::app::concerns::VcsProvider;
use crate::providers::drivers::github::client::GitHubDriver;
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

#[derive(serde::Deserialize)]
struct InstallationTokenResponse {
    token: String,
}

pub async fn resolve_provider_for_repo_owner(
    state: &AppState,
    organization_id: &str,
    owner: &str,
) -> Result<(Arc<dyn VcsProvider>, bool), String> {
    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(organization_id)
    .fetch_one(&state.db_pool)
    .await
    .ok()
    .flatten()
    .ok_or_else(|| "no provider linked to organization".to_string())?;

    let provider_account_login = sqlx::query_scalar::<_, Option<String>>(
        "SELECT account_login FROM providers WHERE id = ?",
    )
    .bind(&provider_id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let credentials = crate::app::providers::credentials::credentials(state, &provider_id)
        .await
        .map_err(|e| e.to_string())?;

    let is_personal_owner = provider_account_login.as_deref() == Some(owner);

    if credentials.kind == ProviderKind::GitHub {
        if let ProviderAuth::GitHubApp { oauth_access_token, installation_token, .. } = credentials.auth {
            let token = if is_personal_owner {
                installation_token
            } else {
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
                        "target_login": owner,
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
                result.token
            };

            let provider = GitHubDriver::new(token).map_err(|e| e.to_string())?;
            return Ok((Arc::new(provider), is_personal_owner));
        }
    }

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|e| e.to_string())?;

    Ok((provider, is_personal_owner))
}

pub async fn resolve_provider_for_org(
    state: &AppState,
    organization_id: &str,
) -> Result<Arc<dyn VcsProvider>, String> {
    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(organization_id)
    .fetch_one(&state.db_pool)
    .await
    .ok()
    .flatten()
    .ok_or_else(|| "no provider linked to organization".to_string())?;

    let credentials = crate::app::providers::credentials::credentials(state, &provider_id)
        .await
        .map_err(|e| e.to_string())?;

    state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|e| e.to_string())
}
