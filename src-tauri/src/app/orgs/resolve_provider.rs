use std::sync::Arc;

use akira_billing::types::GithubInstallationTokenPayload;

use crate::app::concerns::VcsProvider;
use crate::providers::drivers::github::client::{GitHubDriver, GITHUB_API};
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

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
        if let ProviderAuth::GitHubApp { installation_token, .. } = credentials.auth {
            let token = if is_personal_owner {
                installation_token
            } else {
                let installations = {
                    let billing = state.billing.read().await;
                    billing
                        .inner()
                        .me_github_installations()
                        .await
                        .map_err(|e| format!("list installations failed: {e}"))?
                };

                let installation = installations
                    .installations
                    .iter()
                    .find(|i| i.account_login == owner)
                    .ok_or_else(|| format!("no installation found for {owner}"))?;

                let response = {
                    let billing = state.billing.read().await;
                    billing
                        .inner()
                        .github_installation_token(GithubInstallationTokenPayload {
                            installation_id: Some(installation.id),
                        })
                        .await
                        .map_err(|e| format!("installation token request failed: {e}"))?
                };

                response.token
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

#[derive(serde::Deserialize)]
struct GitHubRepoParentOwner {
    login: String,
}

#[derive(serde::Deserialize)]
struct GitHubRepoParent {
    name: String,
    owner: GitHubRepoParentOwner,
}

#[derive(serde::Deserialize)]
struct GitHubRepoResponse {
    parent: Option<GitHubRepoParent>,
}

pub async fn fetch_and_persist_github_parent(
    state: &AppState,
    org_id: &str,
    owner: &str,
    repo_name: &str,
) -> Option<(String, String)> {
    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(org_id)
    .fetch_one(&state.db_pool)
    .await
    .ok()??;

    let credentials = crate::app::providers::credentials::credentials(state, &provider_id)
        .await
        .ok()?;

    let token = match credentials.auth {
        ProviderAuth::PersonalAccessToken { token } => token,
        ProviderAuth::GitHubOAuth { access_token, .. } => access_token,
        ProviderAuth::GitHubApp { installation_token, .. } => installation_token,
        ProviderAuth::AppPassword { .. } => return None,
    };

    let driver = GitHubDriver::new(token).ok()?;
    let url = format!("{GITHUB_API}/repos/{owner}/{repo_name}");
    let response: GitHubRepoResponse = driver.get_json(url).await.ok()?;
    let parent = response.parent?;

    let fork_owner = parent.owner.login;
    let fork_repo = parent.name;

    let _ = sqlx::query(
        "UPDATE organization_repos SET fork_owner = ?, fork_repo = ? WHERE organization_id = ? AND repo_name = ?",
    )
    .bind(&fork_owner)
    .bind(&fork_repo)
    .bind(org_id)
    .bind(repo_name)
    .execute(&state.db_pool)
    .await;

    Some((fork_owner, fork_repo))
}
