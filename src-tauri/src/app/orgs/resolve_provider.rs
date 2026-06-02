use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::RwLock;

use akira_billing::types::GithubInstallationTokenPayload;

use crate::app::concerns::VcsProvider;
use crate::providers::drivers::github::client::{GitHubDriver, GITHUB_API};
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

#[derive(serde::Deserialize, Clone)]
pub struct GitHubInstallation {
    pub id: u64,
    pub account: Account,
}

#[derive(serde::Deserialize, Clone)]
pub struct Account {
    pub login: String,
}

#[derive(serde::Deserialize)]
struct InstallationsResponse {
    installations: Vec<GitHubInstallation>,
}

struct CachedInstallations {
    token: String,
    installations: Vec<GitHubInstallation>,
    cached_at: Instant,
}

struct CachedToken {
    token: String,
    expires_at_unix: i64,
}

lazy_static::lazy_static! {
    static ref INSTALLATIONS_CACHE: RwLock<Option<CachedInstallations>> = RwLock::new(None);
    static ref INSTALLATION_TOKEN_CACHE: std::sync::RwLock<HashMap<u64, CachedToken>> =
        std::sync::RwLock::new(HashMap::new());
}

const CACHE_TTL: Duration = Duration::from_secs(300);
const TOKEN_EXPIRY_BUFFER_SECS: i64 = 60;

fn parse_expiry_unix(value: &str) -> i64 {
    chrono::DateTime::parse_from_rfc3339(value)
        .map(|dt| dt.timestamp())
        .unwrap_or(0)
}

fn token_is_fresh(expires_at_unix: i64, now: i64) -> bool {
    now < expires_at_unix - TOKEN_EXPIRY_BUFFER_SECS
}

pub async fn get_cached_or_mint_token(state: &AppState, installation_id: u64) -> Result<String, String> {
    let now = chrono::Utc::now().timestamp();

    if let Ok(cache) = INSTALLATION_TOKEN_CACHE.read() {
        if let Some(cached) = cache.get(&installation_id) {
            if token_is_fresh(cached.expires_at_unix, now) {
                return Ok(cached.token.clone());
            }
        }
    }

    if let Some(retry_in) = super::throttle::cooldown_remaining(installation_id, now) {
        return Err(format!("installation token throttled; retry in {retry_in}s"));
    }

    let response = {
        let billing = state.billing.read().await;
        match billing
            .inner()
            .github_installation_token(GithubInstallationTokenPayload {
                installation_id: Some(installation_id),
            })
            .await
        {
            Ok(response) => response,
            Err(akira_billing::Error::Throttled { retry_after }) => {
                let cooldown = retry_after.unwrap_or(super::throttle::DEFAULT_THROTTLE_COOLDOWN_SECS);
                super::throttle::set_cooldown(installation_id, now + cooldown as i64);
                return Err(format!("installation token throttled; retry in {cooldown}s"));
            }
            Err(error) => return Err(format!("installation token request failed: {error}")),
        }
    };

    let expires_at_unix = parse_expiry_unix(&response.expires_at);
    if let Ok(mut cache) = INSTALLATION_TOKEN_CACHE.write() {
        cache.insert(
            installation_id,
            CachedToken { token: response.token.clone(), expires_at_unix },
        );
    }

    Ok(response.token)
}

pub fn invalidate_installation_token(installation_id: u64) {
    if let Ok(mut cache) = INSTALLATION_TOKEN_CACHE.write() {
        cache.remove(&installation_id);
    }
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
        if let ProviderAuth::GitHubApp { oauth_access_token, .. } = credentials.auth {
            let installations = get_cached_or_fetch_installations(&oauth_access_token).await?;

            let installation = installations.iter().find(|i| i.account.login == owner);

            let provider = match installation {
                Some(installation) => {
                    let installation_id = installation.id;
                    let token = get_cached_or_mint_token(state, installation_id).await?;
                    GitHubDriver::new(token)
                        .map_err(|e| e.to_string())?
                        .with_user_token(Some(oauth_access_token))
                        .with_auth_failure_hook(Arc::new(move || {
                            invalidate_installation_token(installation_id)
                        }))
                }
                None => GitHubDriver::new(oauth_access_token.clone())
                    .map_err(|e| e.to_string())?
                    .with_user_token(Some(oauth_access_token)),
            };
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

#[cfg(test)]
mod tests;

pub async fn get_cached_or_fetch_installations(token: &str) -> Result<Vec<GitHubInstallation>, String> {
    let cache = INSTALLATIONS_CACHE.read().await;
    if let Some(cached) = cache.as_ref() {
        if cached.token == token && cached.cached_at.elapsed() < CACHE_TTL {
            return Ok(cached.installations.clone());
        }
    }
    drop(cache);

    let driver = GitHubDriver::new(token.to_string()).map_err(|e| e.to_string())?;
    let url = format!("{GITHUB_API}/user/installations");
    let response: InstallationsResponse = driver
        .get_json(url)
        .await
        .map_err(|e| format!("failed to fetch installations: {e}"))?;

    let mut cache = INSTALLATIONS_CACHE.write().await;
    *cache = Some(CachedInstallations {
        token: token.to_string(),
        installations: response.installations.clone(),
        cached_at: Instant::now(),
    });

    Ok(response.installations)
}
