use tauri::State;

use crate::state::AppState;

pub async fn delete(state: State<'_, AppState>, provider_id: String, keep_organizations: bool) -> Result<(), String> {
    if !keep_organizations {
        let organizations = sqlx::query_as::<_, crate::database::records::OrganizationSummary>(
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
            "#,
        )
        .bind(&provider_id)
        .fetch_all(&state.db_pool)
        .await
        .map_err(|error| error.to_string())?;

        for org in organizations {
            sqlx::query("DELETE FROM organizations WHERE id = ?")
                .bind(&org.id)
                .execute(&state.db_pool)
                .await
                .map_err(|error| error.to_string())?;
        }
    }

    state.provider_repo.delete(&provider_id).await.map_err(|error| error.to_string())
}
