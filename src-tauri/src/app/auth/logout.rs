use tauri::State;

use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

pub async fn logout(state: State<'_, AppState>) -> AppResult<()> {
    {
        let mut billing = state.billing.write().await;
        billing.clear_customer_token();
    }

    sqlx::query(
        "UPDATE license SET customer_id = NULL, customer_email = NULL, customer_token_cipher = NULL WHERE id = 'local'",
    )
    .execute(&state.db_pool)
    .await
    .map_err(|error| AppError::Internal(format!("logout db update failed: {error}")))?;

    Ok(())
}
