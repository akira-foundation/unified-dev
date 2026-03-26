use tauri::State;

use crate::database::records::ProviderSummary;
use crate::state::AppState;

pub async fn list(state: State<'_, AppState>) -> Result<Vec<ProviderSummary>, String> {
    sqlx::query_as::<_, ProviderSummary>(
        "SELECT id, name, kind, created_at, account_login, account_type FROM providers ORDER BY created_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}
