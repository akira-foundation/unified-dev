use akira_billing::types::GithubInstallationTokenPayload;
use tauri::State;
use tauri_plugin_opener::OpenerExt;

use crate::app::support::error::{AppError, AppResult};
use crate::database::records::ProviderSummary;
use crate::providers::enums::ProviderAuth;
use crate::state::AppState;

const APP_NOT_INSTALLED_CODE: &str = "github_app_not_installed";

pub async fn connect_github(state: State<'_, AppState>, app: tauri::AppHandle) -> AppResult<ProviderSummary> {
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
                        "GitHub App installation required. Complete the installation in the browser, then click Connect again."
                            .to_string(),
                    ));
                }
                return Err(translate_billing_error(error));
            }
        }
    };

    let expires_at = parse_rfc3339_to_unix(&response.expires_at)
        .ok_or_else(|| AppError::Provider("invalid installation token expiry".to_string()))?;

    let user_token = {
        let billing = state.billing.read().await;
        billing.inner().github_user_token().await.ok()
    };

    let auth = ProviderAuth::GitHubApp {
        oauth_access_token: user_token.as_ref().map(|t| t.token.clone()).unwrap_or_default(),
        oauth_refresh_token: None,
        oauth_expires_at: None,
        installation_token: response.token,
        installation_id: response.installation_id,
        expires_at,
    };

    let (auth_type, auth_payload) = crate::app::providers::credentials::serialize_auth(&state, &auth)
        .map_err(|error| AppError::Provider(error.to_string()))?;

    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;

    let existing: Option<(String, String)> = sqlx::query_as(
        "SELECT id, created_at FROM providers WHERE kind = 'github' AND account_login = ? AND customer_id = ? LIMIT 1",
    )
    .bind(&response.account_login)
    .bind(&customer_id)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| AppError::Provider(e.to_string()))?;

    let (id, created_at) = if let Some((existing_id, existing_created_at)) = existing {
        sqlx::query(
            "UPDATE providers SET name = ?, auth_type = ?, auth_payload = ?, account_login = ?, account_type = ?, customer_id = ? WHERE id = ?",
        )
        .bind(&response.account_login)
        .bind(&auth_type)
        .bind(&auth_payload)
        .bind(&response.account_login)
        .bind(&response.account_type)
        .bind(&customer_id)
        .bind(&existing_id)
        .execute(&state.db_pool)
        .await
        .map_err(|error| AppError::Provider(format!("DB update failed: {error}")))?;
        (existing_id, existing_created_at)
    } else {
        let new_id = uuid::Uuid::new_v4().to_string();
        let new_created_at = time::OffsetDateTime::now_utc()
            .format(&time::format_description::well_known::Rfc3339)
            .unwrap_or_default();
        sqlx::query(
            "INSERT INTO providers (id, name, kind, auth_type, auth_payload, created_at, account_login, account_type, customer_id) VALUES (?, ?, 'github', ?, ?, ?, ?, ?, ?)",
        )
        .bind(&new_id)
        .bind(&response.account_login)
        .bind(&auth_type)
        .bind(&auth_payload)
        .bind(&new_created_at)
        .bind(&response.account_login)
        .bind(&response.account_type)
        .bind(&customer_id)
        .execute(&state.db_pool)
        .await
        .map_err(|error| AppError::Provider(format!("DB insert failed: {error}")))?;
        (new_id, new_created_at)
    };

    Ok(ProviderSummary {
        id,
        name: response.account_login.clone(),
        kind: "github".to_string(),
        auth_type,
        created_at,
        account_login: Some(response.account_login),
        account_type: Some(response.account_type),
    })
}

fn is_app_not_installed(error: &akira_billing::Error) -> bool {
    matches!(
        error,
        akira_billing::Error::Api { status: 412, code, .. } if code == APP_NOT_INSTALLED_CODE
    )
}

fn is_unauthorized(error: &akira_billing::Error) -> bool {
    matches!(error, akira_billing::Error::Api { status: 401, .. })
}

fn translate_billing_error(error: akira_billing::Error) -> AppError {
    use akira_billing::Error as BErr;
    match error {
        BErr::Api { status, code, .. } if !code.is_empty() => {
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
