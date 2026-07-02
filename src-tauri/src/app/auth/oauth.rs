use std::sync::OnceLock;
use std::time::Duration;

use akira_billing::oauth::{
    build_oauth_init_url, generate_oauth_state, generate_pkce_challenge, BuildOauthInitUrl,
};
use akira_billing::types::{OauthExchangeEntitlement, OauthExchangePayload};
use serde::Serialize;
use tauri::State;
use tauri_plugin_opener::OpenerExt;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::sync::oneshot;

use crate::app::billing::client::PRODUCT_SLUG;
use crate::app::profile;
use crate::app::support::error::{AppError, AppResult};
use crate::app::support::security::active_customer_set;
use crate::state::AppState;
use crate::{database, setup};

const CALLBACK_TIMEOUT_SECS: u64 = 300;
const READ_TIMEOUT_SECS: u64 = 15;

static CALLBACK_ABORT: OnceLock<tokio::sync::Mutex<Option<oneshot::Sender<()>>>> = OnceLock::new();

fn abort_slot() -> &'static tokio::sync::Mutex<Option<oneshot::Sender<()>>> {
    CALLBACK_ABORT.get_or_init(|| tokio::sync::Mutex::new(None))
}

#[derive(Debug, Clone, Serialize)]
pub struct OauthEntitlement {
    pub plan_key: Option<String>,
    pub source: String,
    pub ends_at: Option<String>,
}

impl From<OauthExchangeEntitlement> for OauthEntitlement {
    fn from(value: OauthExchangeEntitlement) -> Self {
        Self {
            plan_key: value.plan_key,
            source: value.source,
            ends_at: value.ends_at,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct LoginResult {
    pub customer_id: String,
    pub customer_email: String,
    pub customer_name: Option<String>,
    pub entitlement: Option<OauthEntitlement>,
    pub requires_plan_selection: bool,
}

pub async fn login_with_provider(
    state: State<'_, AppState>,
    app: &tauri::AppHandle,
    provider: &str,
) -> AppResult<LoginResult> {
    let listener = bind_ephemeral_loopback().await?;
    let port = listener
        .local_addr()
        .map_err(|e| AppError::Provider(format!("oauth bind addr: {e}")))?
        .port();
    let redirect_uri = format!("http://127.0.0.1:{port}/cb");

    let pkce = generate_pkce_challenge();
    let oauth_state = generate_oauth_state();
    let base_url = billing_base_url();

    let url = build_oauth_init_url(BuildOauthInitUrl {
        base_url: &base_url,
        provider,
        product: PRODUCT_SLUG,
        redirect_uri: &redirect_uri,
        code_challenge: &pkce.challenge,
        code_challenge_method: None,
        state: Some(&oauth_state),
    });

    app.opener()
        .open_url(&url, None::<&str>)
        .map_err(|e| AppError::Provider(format!("failed to open browser: {e}")))?;

    let (code, returned_state) = await_callback(listener).await?;

    if returned_state != oauth_state {
        return Err(AppError::Provider("oauth state mismatch".to_string()));
    }

    let response = {
        let mut billing = state.billing.write().await;
        let response = billing
            .inner_mut()
            .exchange_oauth_code(OauthExchangePayload {
                code: &code,
                code_verifier: &pkce.verifier,
            })
            .await
            .map_err(|e| translate_billing_error(e, "oauth_exchange"))?;
        billing.set_customer_token(response.access_token.clone());
        response
    };

    if let Err(err) = database::migrate_legacy_if_needed(app, &response.customer.id).await {
        eprintln!("legacy db migration skipped: {err}");
    }

    let pool = database::open_customer_pool(app, &response.customer.id).await?;
    state.set_pool(pool.clone()).await;

    persist_customer_session(&pool, &state.token_cipher, &response).await?;
    active_customer_set(&response.customer.id)?;

    let _ = profile::set(&response.customer.email, &pool).await;

    setup::start_background_services(app, &pool).await;

    Ok(LoginResult {
        customer_id: response.customer.id,
        customer_email: response.customer.email,
        customer_name: response.customer.name,
        entitlement: response.entitlement.map(OauthEntitlement::from),
        requires_plan_selection: response.requires_plan_selection,
    })
}

fn billing_base_url() -> String {
    crate::app::billing::base_url(option_env!("AKIRA_BILLING_URL").unwrap_or(""))
}

async fn bind_ephemeral_loopback() -> AppResult<TcpListener> {
    if let Some(sender) = abort_slot().lock().await.take() {
        let _ = sender.send(());
        tokio::time::sleep(Duration::from_millis(150)).await;
    }

    TcpListener::bind("127.0.0.1:0")
        .await
        .map_err(|e| AppError::Provider(format!("failed to bind oauth callback: {e}")))
}

async fn await_callback(listener: TcpListener) -> AppResult<(String, String)> {
    let (cancel_tx, mut cancel_rx) = oneshot::channel();
    *abort_slot().lock().await = Some(cancel_tx);

    let accept_result = tokio::select! {
        result = tokio::time::timeout(Duration::from_secs(CALLBACK_TIMEOUT_SECS), listener.accept()) => {
            result.map_err(|_| AppError::Provider("oauth callback timed out".to_string()))?
        }
        _ = &mut cancel_rx => {
            return Err(AppError::Provider("oauth callback cancelled".to_string()));
        }
    };

    *abort_slot().lock().await = None;

    let (mut stream, _) =
        accept_result.map_err(|e| AppError::Provider(format!("oauth accept: {e}")))?;

    let mut buf = vec![0u8; 8192];
    let n = tokio::time::timeout(
        Duration::from_secs(READ_TIMEOUT_SECS),
        stream.read(&mut buf),
    )
    .await
    .map_err(|_| AppError::Provider("oauth callback read timed out".to_string()))?
    .map_err(|e| AppError::Provider(format!("oauth callback read: {e}")))?;
    let request = String::from_utf8_lossy(&buf[..n]);

    let path = request
        .lines()
        .next()
        .and_then(|line| line.split_whitespace().nth(1))
        .ok_or_else(|| AppError::Provider("oauth callback path missing".to_string()))?;

    let callback_url = format!("http://localhost{path}");
    let url = reqwest::Url::parse(&callback_url)
        .map_err(|e| AppError::Provider(format!("invalid oauth callback url: {e}")))?;

    let code = url
        .query_pairs()
        .find(|(key, _)| key == "code")
        .map(|(_, value)| value.into_owned())
        .ok_or_else(|| AppError::Provider("oauth code missing".to_string()))?;

    let state = url
        .query_pairs()
        .find(|(key, _)| key == "state")
        .map(|(_, value)| value.into_owned())
        .ok_or_else(|| AppError::Provider("oauth state missing".to_string()))?;

    let body = include_str!("oauth_success.html");
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        body.len(),
        body
    );
    let _ = stream.write_all(response.as_bytes()).await;

    Ok((code, state))
}

async fn persist_customer_session(
    pool: &sqlx::SqlitePool,
    token_cipher: &crate::app::support::security::TokenCipher,
    response: &akira_billing::types::OauthExchangeResponse,
) -> AppResult<()> {
    let encrypted_token = token_cipher.encrypt(&response.access_token)?;
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO license (
            id, token, plan, cycle, email, status, valid_until, activated_at,
            last_verified_at, signature, customer_id, customer_email,
            customer_token_cipher
         )
         VALUES ('local', '', '', '', ?, 'pending', '', ?, ?, '', ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
            email = excluded.email,
            customer_id = excluded.customer_id,
            customer_email = excluded.customer_email,
            customer_token_cipher = excluded.customer_token_cipher,
            last_verified_at = excluded.last_verified_at",
    )
    .bind(&response.customer.email)
    .bind(&now)
    .bind(&now)
    .bind(&response.customer.id)
    .bind(&response.customer.email)
    .bind(&encrypted_token)
    .execute(pool)
    .await?;

    Ok(())
}

fn translate_billing_error(err: akira_billing::Error, context: &str) -> AppError {
    use akira_billing::Error as BErr;
    match err {
        BErr::Api { status, code, .. } => {
            if !code.is_empty() {
                AppError::Internal(code)
            } else {
                AppError::Internal(format!("billing {context} failed: HTTP {status}"))
            }
        }
        other => AppError::Internal(format!("billing {context}: {other}")),
    }
}
