use tauri::State;

use crate::database::records::OrganizationSummary;
use crate::state::AppState;

pub async fn list_by_provider(state: State<'_, AppState>, provider_id: String) -> Result<Vec<OrganizationSummary>, String> {
    sqlx::query_as::<_, OrganizationSummary>(
        "SELECT id, name, provider_id, external_id, created_at FROM organizations WHERE provider_id = ? ORDER BY name",
    )
    .bind(&provider_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}
