use tauri::State;

use crate::state::AppState;
use crate::app::support::error::AppResult;

use super::types::InstalledSkill;

pub async fn get(state: State<'_, AppState>) -> AppResult<Vec<InstalledSkill>> {
    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    let rows = sqlx::query_as::<_, (String, String, String, bool, Option<String>, String, String, String)>(
        "SELECT id, name, description, enabled, icon_path, installed_at, source_path, scope FROM skills WHERE customer_id = ? ORDER BY name COLLATE NOCASE",
    )
    .bind(&customer_id)
    .fetch_all(&state.db_pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|(id, name, description, enabled, icon_path, installed_at, source_path, scope)| InstalledSkill {
            id,
            name,
            description,
            enabled,
            icon_path,
            installed_at,
            source_path,
            scope,
        })
        .collect())
}
