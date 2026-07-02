use tauri::State;

use crate::app::support::error::AppResult;
use crate::app::support::security::active_customer_clear;
use crate::state::AppState;

pub async fn logout(state: State<'_, AppState>) -> AppResult<()> {
    {
        let mut billing = state.billing.write().await;
        billing.clear_customer_token();
    }

    let _ = crate::app::remote::stop().await;
    crate::app::orgs::resolve_provider::clear_installation_caches().await;
    state.clear_pool().await;
    active_customer_clear()?;

    Ok(())
}
