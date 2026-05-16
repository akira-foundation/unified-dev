use tauri::State;

use crate::app::auth::oauth::login_with_provider;
use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn ensure_authenticated(
    state: State<'_, AppState>,
    app: &tauri::AppHandle,
    provider: &str,
) -> AppResult<()> {
    let already = {
        let billing = state.billing.read().await;
        billing.has_customer_token()
    };
    if already {
        return Ok(());
    }
    let _ = login_with_provider(state, app, provider).await?;
    Ok(())
}
