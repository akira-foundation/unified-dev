use tauri::State;

use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn logout(state: State<'_, AppState>) -> AppResult<()> {
    let pool = state.db_pool.clone();
    let billing = state.billing.clone();

    tokio::spawn(async move {
        {
            let mut client = billing.write().await;
            client.clear_customer_token();
        }
        let _ = sqlx::query(
            "UPDATE license SET customer_id = NULL, customer_email = NULL, customer_token_cipher = NULL WHERE id = 'local'",
        )
        .execute(&pool)
        .await;
    });

    Ok(())
}
