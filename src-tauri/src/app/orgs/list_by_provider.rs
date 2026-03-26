use tauri::State;

use crate::database::records::OrganizationSummary;
use crate::state::AppState;

pub async fn list_by_provider(state: State<'_, AppState>, provider_id: String) -> Result<Vec<OrganizationSummary>, String> {
    sqlx::query_as::<_, OrganizationSummary>(
        r#"
        SELECT
            o.id,
            o.name,
            o.provider_id,
            o.external_id,
            o.created_at,
            COUNT(CASE WHEN r.is_selected = 1 THEN 1 END) AS selected_repos_count,
            ss.updated_at AS last_synced_at
        FROM organizations o
        LEFT JOIN organization_repos r ON r.organization_id = o.id
        LEFT JOIN sync_settings ss ON ss.id = o.id
        WHERE o.provider_id = ?
        GROUP BY o.id
        ORDER BY o.name
        "#,
    )
    .bind(&provider_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}
