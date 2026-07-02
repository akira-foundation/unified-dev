use tauri::State;

use crate::state::AppState;

pub async fn delete(
    state: State<'_, AppState>,
    provider_id: String,
    keep_organizations: bool,
) -> Result<(), String> {
    let pool = state.pool().await.map_err(|e| e.to_string())?;
    let mut transaction = pool.begin().await.map_err(|e| e.to_string())?;

    if keep_organizations {
        sqlx::query("UPDATE organizations SET provider_id = NULL WHERE provider_id = ?")
            .bind(&provider_id)
            .execute(&mut *transaction)
            .await
            .map_err(|e| e.to_string())?;
    } else {
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
