use tauri::State;

use crate::state::AppState;

pub async fn delete(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    sqlx::query("DELETE FROM organizations WHERE id = ?")
        .bind(&organization_id)
        .execute(&state.pool().await.map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}
