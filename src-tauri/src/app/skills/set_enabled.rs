use tauri::State;

use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn set_enabled(id: String, enabled: bool, state: State<'_, AppState>) -> AppResult<()> {
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    sqlx::query("UPDATE skills SET enabled = ? WHERE id = ? AND customer_id IS ?")
        .bind(enabled)
        .bind(&id)
        .bind(&customer_id)
        .execute(&state.pool().await?)
        .await?;
    Ok(())
}
