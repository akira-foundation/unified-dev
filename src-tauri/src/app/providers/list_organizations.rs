use std::collections::HashSet;
use std::time::{Duration, Instant};
use tauri::{AppHandle, State};
use tokio::sync::RwLock;

use crate::providers::dto::ProviderOrg;
use crate::providers::enums::{ProviderAuth, ProviderKind, ProviderOrgKind};
use crate::providers::drivers::github::client::{GitHubDriver, GITHUB_API};
use crate::state::AppState;

#[derive(serde::Deserialize, Clone)]
struct GitHubUser {
    id: u64,
    login: String,
}

#[derive(serde::Deserialize, Clone)]
struct GitHubInstallationFull {
    account: Account,
    html_url: String,
}

#[derive(serde::Deserialize, Clone)]
struct Account {
    login: String,
    #[serde(rename = "type")]
    account_type: String,
    id: u64,
}

#[derive(serde::Deserialize, Clone)]
struct UserInstallationsResponse {
    user: GitHubUser,
    installations: Vec<GitHubInstallationFull>,
}

struct CachedUserInstallations {
    data: UserInstallationsResponse,
    cached_at: Instant,
}

lazy_static::lazy_static! {
    static ref USER_INSTALLATIONS_CACHE: RwLock<Option<CachedUserInstallations>> = RwLock::new(None);
}

const USER_CACHE_TTL: Duration = Duration::from_secs(300);

pub async fn list_organizations(state: State<'_, AppState>, app: AppHandle, provider_id: String) -> Result<Vec<ProviderOrg>, String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &provider_id)
        .await
        .map_err(|error| error.to_string())?;

    if credentials.kind == ProviderKind::GitHub {
        if matches!(credentials.auth, ProviderAuth::GitHubApp { .. }) {
            return list_github_organizations(state, app).await;
        }
    }

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|error| error.to_string())?;

    provider
        .list_organizations()
        .await
        .map_err(|error| error.to_string())
}

async fn list_github_organizations(state: State<'_, AppState>, app: AppHandle) -> Result<Vec<ProviderOrg>, String> {
    crate::app::auth::ensure_authenticated(state.clone(), &app, "github")
        .await
        .map_err(|error| error.to_string())?;

    let provider_id = sqlx::query_scalar::<_, String>(
        "SELECT id FROM providers WHERE kind = 'github' LIMIT 1",
    )
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?
    .ok_or_else(|| "no github provider found".to_string())?;

    let credentials = crate::app::providers::credentials::credentials(&state, &provider_id)
        .await
        .map_err(|e| e.to_string())?;

    let token = match credentials.auth {
        ProviderAuth::GitHubApp { oauth_access_token, .. } => oauth_access_token,
        _ => return Err("not a github app provider".to_string()),
    };

    let response = get_cached_or_fetch_user_installations(&token).await?;

    let installed_logins: HashSet<String> = response
        .installations
        .iter()
        .map(|installation| installation.account.login.clone())
        .collect();

    let mut organizations = Vec::new();

    organizations.push(ProviderOrg {
        id: response.user.id.to_string(),
        login: response.user.login.clone(),
        kind: ProviderOrgKind::Personal,
        app_installed: Some(installed_logins.contains(&response.user.login)),
        app_install_url: (!installed_logins.contains(&response.user.login)).then(|| {
            format!("https://github.com/apps/akira/installations/new")
        }),
        app_manage_url: response
            .installations
            .iter()
            .find(|installation| installation.account.login == response.user.login)
            .map(|installation| installation.html_url.clone()),
    });

    for installation in response.installations.iter() {
        if installation.account.account_type != "Organization" {
            continue;
        }

        let is_installed = installed_logins.contains(&installation.account.login);

        organizations.push(ProviderOrg {
            id: installation.account.id.to_string(),
            login: installation.account.login.clone(),
            kind: ProviderOrgKind::Organization,
            app_installed: Some(is_installed),
            app_install_url: (!is_installed).then(|| {
                format!(
                    "https://github.com/organizations/{}/settings/installations/new",
                    installation.account.login
                )
            }),
            app_manage_url: is_installed.then(|| installation.html_url.clone()),
        });
    }

    organizations.sort_by(|a, b| {
        let a_order = matches!(a.kind, ProviderOrgKind::Personal) as u8;
        let b_order = matches!(b.kind, ProviderOrgKind::Personal) as u8;
        b_order.cmp(&a_order).then(a.login.cmp(&b.login))
    });

    Ok(organizations)
}

async fn get_cached_or_fetch_user_installations(token: &str) -> Result<UserInstallationsResponse, String> {
    let cache = USER_INSTALLATIONS_CACHE.read().await;
    if let Some(cached) = cache.as_ref() {
        if cached.cached_at.elapsed() < USER_CACHE_TTL {
            return Ok(cached.data.clone());
        }
    }
    drop(cache);

    let driver = GitHubDriver::new(token.to_string()).map_err(|e| e.to_string())?;
    let url = format!("{GITHUB_API}/user/installations");
    let response: UserInstallationsResponse = driver
        .get_json(url)
        .await
        .map_err(|e| format!("failed to fetch user installations: {e}"))?;

    let mut cache = USER_INSTALLATIONS_CACHE.write().await;
    *cache = Some(CachedUserInstallations {
        data: response.clone(),
        cached_at: Instant::now(),
    });

    Ok(response)
}

