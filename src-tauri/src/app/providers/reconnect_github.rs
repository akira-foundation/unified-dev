use akira_billing::types::GithubInstallationTokenPayload;
use tauri::State;
use tauri_plugin_opener::OpenerExt;

use crate::app::support::error::{AppError, AppResult};
use crate::database::records::ProviderSummary;
use crate::providers::enums::ProviderAuth;
use crate::state::AppState;

const APP_NOT_INSTALLED_CODE: &str = "github_app_not_installed";

pub async fn reconnect_github(
    state: State<'_, AppState>,
    app: tauri::AppHandle,
    provider_id: String,
) -> AppResult<ProviderSummary> {
    crate::app::auth::ensure_authenticated(state.clone(), &app, "github").await?;

    let mut attempt = 0;
    let response = loop {
        let result = {
            let billing = state.billing.read().await;
            billing
                .inner()
                .github_installation_token(GithubInstallationTokenPayload::default())
                .await
        };

        match result {
            Ok(value) => break value,
            Err(error) => {
                if is_unauthorized(&error) && attempt == 0 {
                    attempt += 1;
                    crate::app::auth::login_with_provider(state.clone(), &app, "github").await?;
                    continue;
                }
                if is_app_not_installed(&error) {
                    if let Ok(info) = {
                        let billing = state.billing.read().await;
                        billing.inner().github_app_info().await
                    } {
                        let _ = app.opener().open_url(&info.install_url, None::<&str>);
                    }
                    return Err(AppError::Provider(
                        "GitHub App installation required. Complete the installation in the browser, then click Reconnect again."
                            .to_string(),
                    ));
                }
                return Err(translate_billing_error(error));
            }
        }
    };

    let expires_at = parse_rfc3339_to_unix(&response.expires_at)
        .ok_or_else(|| AppError::Provider("invalid installation token expiry".to_string()))?;

    let auth = ProviderAuth::GitHubApp {
        oauth_access_token: String::new(),
        oauth_refresh_token: None,
        oauth_expires_at: None,
        installation_token: response.token,
        installation_id: response.installation_id,
        expires_at,
    };

    let (auth_type, auth_payload) = crate::app::providers::credentials::serialize_auth(&state, &auth)
        .map_err(|error| AppError::Provider(error.to_string()))?;

    let rows = sqlx::query(
        "UPDATE providers SET auth_type = ?, auth_payload = ?, account_login = ?, account_type = ? WHERE id = ? AND kind = 'github'",
    )
    .bind(&auth_type)
    .bind(&auth_payload)
    .bind(&response.account_login)
    .bind(&response.account_type)
    .bind(&provider_id)
    .execute(&state.db_pool)
    .await
    .map_err(|error| AppError::Provider(format!("DB update failed: {error}")))?;

    if rows.rows_affected() == 0 {
        return Err(AppError::Provider("Provider not found".to_string()));
    }

    let provider = sqlx::query_as::<_, ProviderSummary>(
        "SELECT id, name, kind, auth_type, auth_payload, created_at, account_login, account_type FROM providers WHERE id = ?",
    )
    .bind(&provider_id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|error| AppError::Provider(format!("DB fetch failed: {error}")))?;

    Ok(provider)
}

fn is_app_not_installed(error: &akira_billing::Error) -> bool {
    matches!(
        error,
        akira_billing::Error::Api { status: 412, code } if code == APP_NOT_INSTALLED_CODE
    )
}

fn is_unauthorized(error: &akira_billing::Error) -> bool {
    matches!(error, akira_billing::Error::Api { status: 401, .. })
}

fn translate_billing_error(error: akira_billing::Error) -> AppError {
    use akira_billing::Error as BErr;
    match error {
        BErr::Api { status, code } if !code.is_empty() => {
            AppError::Provider(format!("github_installation_token failed ({status}): {code}"))
        }
        BErr::Api { status, .. } => {
            AppError::Provider(format!("github_installation_token failed: HTTP {status}"))
        }
        other => AppError::Provider(format!("github_installation_token: {other}")),
    }
}

fn parse_rfc3339_to_unix(value: &str) -> Option<i64> {
    time::OffsetDateTime::parse(value, &time::format_description::well_known::Rfc3339)
        .ok()
        .map(|dt| dt.unix_timestamp())
}
