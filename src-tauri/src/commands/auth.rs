use tauri::{AppHandle, State};

use crate::app::auth::{login_with_provider, logout, LoginResult};
use crate::app::support::error::AppResult;
use crate::state::AppState;

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
