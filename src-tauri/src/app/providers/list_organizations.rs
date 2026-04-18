use tauri::State;
use std::collections::HashSet;

use crate::app::support::error::AppResult;
use crate::providers::dto::ProviderOrg;
use crate::providers::drivers::github::client::GitHubDriver;
use crate::providers::enums::{ProviderAuth, ProviderKind, ProviderOrgKind};
use crate::state::AppState;

#[derive(serde::Deserialize)]
struct UserInstallationsResponse {
    installations: Vec<UserInstallation>,
}

#[derive(serde::Deserialize)]
struct UserInstallation {
    #[allow(dead_code)]
    id: u64,
    html_url: String,
    account: InstallationAccount,
}

#[derive(serde::Deserialize)]
struct InstallationAccount {
    id: u64,
    login: String,
    #[serde(rename = "type")]
    kind: String,
}

#[derive(serde::Deserialize)]
struct GitHubUser {
    id: u64,
    login: String,
}

async fn list_installed_logins(driver: &GitHubDriver) -> AppResult<HashSet<String>> {
    let mut page = 1;
    let mut installed_logins = HashSet::new();

    loop {
        let response: UserInstallationsResponse = driver
            .get_json(format!(
                "https://api.github.com/user/installations?per_page=100&page={page}"
            ))
            .await?;

        let count = response.installations.len();
        for installation in response.installations {
            installed_logins.insert(installation.account.login);
        }

        if count < 100 {
            break;
        }

        page += 1;
    }

    Ok(installed_logins)
}

async fn list_user_installations(driver: &GitHubDriver) -> AppResult<Vec<UserInstallation>> {
    let mut page = 1;
    let mut installations = Vec::new();

    loop {
        let response: UserInstallationsResponse = driver
            .get_json(format!(
                "https://api.github.com/user/installations?per_page=100&page={page}"
            ))
            .await?;

        let count = response.installations.len();
        installations.extend(response.installations);

        if count < 100 {
            break;
        }

        page += 1;
    }

    Ok(installations)
}

pub async fn list_organizations(state: State<'_, AppState>, provider_id: String) -> Result<Vec<ProviderOrg>, String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &provider_id)
        .await
        .map_err(|error| error.to_string())?;

    if credentials.kind == ProviderKind::GitHub {
        if let ProviderAuth::GitHubApp { oauth_access_token, .. } = credentials.auth.clone() {
            let provider = GitHubDriver::new(oauth_access_token)
                .map_err(|error| error.to_string())?;

            let app_slug = option_env!("GITHUB_APP_SLUG").unwrap_or("akira-apps-unified-dev");
            let generic_install_url = format!("https://github.com/apps/{app_slug}/installations/new");

            let installed_logins = list_installed_logins(&provider)
                .await
                .map_err(|error| error.to_string())?;

            let installations = list_user_installations(&provider)
                .await
                .map_err(|error| error.to_string())?;

            let personal: GitHubUser = provider
                .get_json("https://api.github.com/user".to_string())
                .await
                .map_err(|error| error.to_string())?;

            let mut organizations = Vec::new();
            organizations.push(ProviderOrg {
                id: personal.id.to_string(),
                login: personal.login.clone(),
                kind: crate::providers::enums::ProviderOrgKind::Personal,
                app_installed: Some(installed_logins.contains(&personal.login)),
                app_install_url: (!installed_logins.contains(&personal.login)).then(|| generic_install_url.clone()),
                app_manage_url: installations
                    .iter()
                    .find(|installation| installation.account.login == personal.login)
                    .map(|installation| installation.html_url.clone()),
            });

            organizations.extend(installations.into_iter().filter_map(|installation| {
                if installation.account.kind != "Organization" {
                    return None;
                }

                let is_installed = installed_logins.contains(&installation.account.login);

                Some(ProviderOrg {
                    id: installation.account.id.to_string(),
                    login: installation.account.login.clone(),
                    kind: crate::providers::enums::ProviderOrgKind::Organization,
                    app_installed: Some(is_installed),
                    app_install_url: (!is_installed).then(|| {
                        format!(
                            "https://github.com/organizations/{}/settings/installations/new",
                            installation.account.login
                        )
                    }),
                    app_manage_url: is_installed.then_some(installation.html_url),
                })
            }));

            organizations.sort_by(|a, b| {
                let a_order = matches!(a.kind, ProviderOrgKind::Personal) as u8;
                let b_order = matches!(b.kind, ProviderOrgKind::Personal) as u8;

                b_order.cmp(&a_order).then(a.login.cmp(&b.login))
            });

            return Ok(organizations);
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
