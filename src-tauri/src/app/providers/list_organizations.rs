use std::collections::HashSet;
use tauri::{AppHandle, State};

use crate::providers::dto::ProviderOrg;
use crate::providers::enums::{ProviderAuth, ProviderKind, ProviderOrgKind};
use crate::state::AppState;

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

    let mut attempt = 0;
    let (info, response) = loop {
        let result = {
            let billing = state.billing.read().await;
            let info = billing.inner().github_app_info().await;
            let response = billing.inner().me_github_installations().await;
            (info, response)
        };

        match result {
            (Ok(info), Ok(response)) => break (info, response),
            (_, Err(error)) if is_unauthorized(&error) && attempt == 0 => {
                attempt += 1;
                crate::app::auth::login_with_provider(state.clone(), &app, "github")
                    .await
                    .map_err(|err| err.to_string())?;
                continue;
            }
            (Err(error), _) => return Err(format!("github app info failed: {error}")),
            (_, Err(error)) => return Err(format!("github installations failed: {error}")),
        }
    };

    let generic_install_url = info.install_url.replace("/installations/select_target", "/installations/new");

    let installed_logins: HashSet<String> = response
        .installations
        .iter()
        .map(|installation| installation.account_login.clone())
        .collect();

    let mut organizations = Vec::new();

    organizations.push(ProviderOrg {
        id: response.user.id.to_string(),
        login: response.user.login.clone(),
        kind: ProviderOrgKind::Personal,
        app_installed: Some(installed_logins.contains(&response.user.login)),
        app_install_url: (!installed_logins.contains(&response.user.login)).then(|| generic_install_url.clone()),
        app_manage_url: response
            .installations
            .iter()
            .find(|installation| installation.account_login == response.user.login)
            .map(|installation| installation.html_url.clone()),
    });

    for installation in response.installations.iter() {
        if installation.account_type != "Organization" {
            continue;
        }

        let is_installed = installed_logins.contains(&installation.account_login);

        organizations.push(ProviderOrg {
            id: installation.account_id.to_string(),
            login: installation.account_login.clone(),
            kind: ProviderOrgKind::Organization,
            app_installed: Some(is_installed),
            app_install_url: (!is_installed).then(|| {
                format!(
                    "https://github.com/organizations/{}/settings/installations/new",
                    installation.account_login
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

fn is_unauthorized(error: &akira_billing::Error) -> bool {
    matches!(error, akira_billing::Error::Api { status: 401, .. })
}
