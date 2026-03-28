use tauri::State;

use crate::state::AppState;

pub async fn delete(state: State<'_, AppState>, provider_id: String, keep_organizations: bool) -> Result<(), String> {
    let mut transaction = state.db_pool.begin().await.map_err(|e| e.to_string())?;

    if !keep_organizations {
        sqlx::query("DELETE FROM organizations WHERE provider_id = ?")
            .bind(&provider_id)
            .execute(&mut *transaction)
            .await
            .map_err(|e| e.to_string())?;
    }

    sqlx::query("DELETE FROM providers WHERE id = ?")
        .bind(&provider_id)
        .execute(&mut *transaction)
        .await
        .map_err(|e| e.to_string())?;

    transaction.commit().await.map_err(|e| e.to_string())?;

    Ok(())
}
