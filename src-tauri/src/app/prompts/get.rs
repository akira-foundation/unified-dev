use std::collections::HashMap;

use tauri::State;

use crate::state::AppState;
use crate::support::error::AppResult;

pub async fn get_prompts(state: State<'_, AppState>) -> AppResult<HashMap<String, String>> {
    let rows = sqlx::query_as::<_, (String, String)>("SELECT action, content FROM prompts")
        .fetch_all(&state.db_pool)
        .await?;

    Ok(rows.into_iter().collect())
}
