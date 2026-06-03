use tauri::State;

use crate::database::records::ProviderSummary;
use crate::state::AppState;

pub async fn list(state: State<'_, AppState>) -> Result<Vec<ProviderSummary>, String> {
    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    sqlx::query_as::<_, ProviderSummary>(
        "SELECT id, name, kind, auth_type, created_at, account_login, account_type FROM providers WHERE customer_id = ? ORDER BY created_at DESC",
    )
    .bind(customer_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}
