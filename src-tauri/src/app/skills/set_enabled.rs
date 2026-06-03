use tauri::State;

use crate::state::AppState;
use crate::app::support::error::AppResult;

pub async fn set_enabled(id: String, enabled: bool, state: State<'_, AppState>) -> AppResult<()> {
    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    sqlx::query("UPDATE skills SET enabled = ? WHERE id = ? AND customer_id IS ?")
        .bind(enabled)
        .bind(&id)
        .bind(&customer_id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}
