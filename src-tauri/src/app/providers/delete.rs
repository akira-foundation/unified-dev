use tauri::State;

use crate::state::AppState;

pub async fn delete(state: State<'_, AppState>, provider_id: String, keep_organizations: bool) -> Result<(), String> {
    if !keep_organizations {
        let organizations = sqlx::query_as::<_, crate::database::models::OrganizationSummary>(
            "SELECT id, name, provider_id, external_id, created_at FROM organizations WHERE provider_id = ?",
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
