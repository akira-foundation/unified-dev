use tauri::State;

use crate::database::models::OrganizationSummary;
use crate::state::AppState;

pub async fn list(state: State<'_, AppState>) -> Result<Vec<OrganizationSummary>, String> {
    sqlx::query_as::<_, OrganizationSummary>(
        "SELECT id, name, provider_id, external_id, created_at FROM organizations ORDER BY name",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}
