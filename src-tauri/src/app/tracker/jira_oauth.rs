use std::sync::OnceLock;
use std::time::Duration;

use tauri::AppHandle;
use tauri_plugin_opener::OpenerExt;
use tokio::sync::{oneshot, Mutex};

use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;
use crate::tracker::dto::TrackerNamed;
use crate::tracker::drivers::jira::JiraOauthBundle;

const REDIRECT_URI: &str = "akira://oauth/jira";

type Pending = Mutex<Option<oneshot::Sender<(String, String)>>>;

fn pending() -> &'static Pending {
    static PENDING: OnceLock<Pending> = OnceLock::new();
    PENDING.get_or_init(|| Mutex::new(None))
}

pub async fn deliver(code: String, state: String) {
    if let Some(sender) = pending().lock().await.take() {
        let _ = sender.send((code, state));
    }
}

pub async fn connect(state: &AppState, app: &AppHandle) -> AppResult<TrackerNamed> {
    let pkce = akira_billing::oauth::generate_pkce_challenge();
    let oauth_state = akira_billing::oauth::generate_oauth_state();

    let url = state
        .billing
        .read()
        .await
        .jira_connect_url(REDIRECT_URI, &pkce.challenge, &oauth_state);

    let (sender, receiver) = oneshot::channel();
    *pending().lock().await = Some(sender);

    app.opener()
        .open_url(&url, None::<&str>)
        .map_err(|err| AppError::Provider(format!("could not open browser: {err}")))?;

    let (code, returned_state) = tokio::time::timeout(Duration::from_secs(300), receiver)
        .await
        .map_err(|_| AppError::Provider("Jira authorization timed out.".to_string()))?
        .map_err(|_| AppError::Provider("Jira authorization cancelled.".to_string()))?;

    if returned_state != oauth_state {
        return Err(AppError::Provider("Jira authorization state mismatch.".to_string()));
    }

    let tokens = state.billing.read().await.jira_exchange(&code, &pkce.verifier).await?;

    let sites = issue_provider_jira::accessible_resources(&tokens.access_token)
        .await
        .map_err(|err| AppError::Provider(format!("could not list Jira sites: {err}")))?;
    let site = sites
        .into_iter()
        .next()
        .ok_or_else(|| AppError::Provider("No Jira sites are accessible with this account.".to_string()))?;

    let bundle = JiraOauthBundle {
        cloud_id: site.cloud_id,
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        expires_at: expires_at(tokens.expires_in),
    };
    let json = serde_json::to_string(&bundle)
        .map_err(|err| AppError::Provider(format!("could not serialize credentials: {err}")))?;

    super::connect(state, "jira".to_string(), json).await
}

pub async fn ensure_fresh(state: &AppState, token: String) -> AppResult<String> {
    let bundle: JiraOauthBundle = match serde_json::from_str(&token) {
        Ok(bundle) => bundle,
        Err(_) => return Ok(token),
    };

    if !is_expiring(bundle.expires_at.as_deref()) {
        return Ok(token);
    }

    let Some(refresh_token) = bundle.refresh_token.clone() else {
        return Ok(token);
    };

    let tokens = state.billing.read().await.jira_refresh(&refresh_token).await?;

    let updated = JiraOauthBundle {
        cloud_id: bundle.cloud_id,
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token.or(Some(refresh_token)),
        expires_at: expires_at(tokens.expires_in).or(bundle.expires_at),
    };
    let json = serde_json::to_string(&updated)
        .map_err(|err| AppError::Provider(format!("could not serialize credentials: {err}")))?;

    let encrypted = state.token_cipher.encrypt(&json)?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query("UPDATE tracker_credentials SET token_cipher = ?, updated_at = ? WHERE provider = 'jira'")
        .bind(&encrypted)
        .bind(&now)
        .execute(&state.db_pool)
        .await?;

    Ok(json)
}

fn expires_at(expires_in: i64) -> Option<String> {
    if expires_in > 0 {
        Some((chrono::Utc::now() + chrono::Duration::seconds(expires_in)).to_rfc3339())
    } else {
        None
    }
}

fn is_expiring(expires_at: Option<&str>) -> bool {
    expires_at
        .and_then(|value| chrono::DateTime::parse_from_rfc3339(value).ok())
        .map(|exp| exp <= chrono::Utc::now() + chrono::Duration::seconds(60))
        .unwrap_or(false)
}
