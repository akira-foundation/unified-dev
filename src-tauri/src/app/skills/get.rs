use tauri::State;

use crate::state::AppState;
use crate::support::error::AppResult;

use super::types::InstalledSkill;

pub async fn get(state: State<'_, AppState>) -> AppResult<Vec<InstalledSkill>> {
    let rows = sqlx::query_as::<_, (String, String, String, bool, Option<String>, String, String)>(
        "SELECT id, name, description, enabled, icon_path, installed_at, source_path FROM skills ORDER BY name COLLATE NOCASE",
    )
    .fetch_all(&state.db_pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|(id, name, description, enabled, icon_path, installed_at, source_path)| InstalledSkill {
            id,
            name,
            description,
            enabled,
            icon_path,
            installed_at,
            source_path,
        })
        .collect())
}
