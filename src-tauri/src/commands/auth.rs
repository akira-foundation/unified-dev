use serde::Serialize;
use tauri::{AppHandle, State};

use crate::app::auth::{login_with_provider, logout, LoginResult};
use crate::app::billing::PRODUCT_SLUG;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

#[derive(Debug, Serialize)]
pub struct OauthProviderDto {
    pub provider: String,
    pub label: String,
    pub scopes: Vec<String>,
}

#[tauri::command]
pub async fn oauth_login(
    provider: String,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<LoginResult> {
    login_with_provider(state, &app, &provider).await
}

#[tauri::command]
pub async fn oauth_logout(state: State<'_, AppState>) -> AppResult<()> {
    logout(state).await
}

#[tauri::command]
pub async fn is_authenticated(state: State<'_, AppState>) -> AppResult<bool> {
    let billing = state.billing.read().await;
    Ok(billing.has_customer_token())
}

#[tauri::command]
pub async fn list_oauth_providers(state: State<'_, AppState>) -> AppResult<Vec<OauthProviderDto>> {
    let response = {
        let billing = state.billing.read().await;
        billing
            .inner()
            .list_oauth_providers(PRODUCT_SLUG)
            .await
            .map_err(|error| AppError::Internal(format!("list oauth providers failed: {error}")))?
    };

    Ok(response
        .providers
        .into_iter()
        .map(|info| OauthProviderDto {
            provider: format!("{:?}", info.provider).to_lowercase(),
            label: info.label,
            scopes: info.scopes,
        })
        .collect())
}
