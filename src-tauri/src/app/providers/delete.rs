use tauri::State;

use crate::state::AppState;

pub async fn delete(state: State<'_, AppState>, provider_id: String, keep_organizations: bool) -> Result<(), String> {
    if !keep_organizations {
        let org_ids = sqlx::query_scalar::<_, String>(
            "SELECT id FROM organizations WHERE provider_id = ?",
        )
        .bind(&provider_id)
        .fetch_all(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

        for org_id in org_ids {
            sqlx::query("DELETE FROM organizations WHERE id = ?")
                .bind(&org_id)
                .execute(&state.db_pool)
                .await
                .map_err(|e| e.to_string())?;
        }
    }

    sqlx::query("DELETE FROM providers WHERE id = ?")
        .bind(&provider_id)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}
