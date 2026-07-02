use std::collections::HashMap;

use tauri::State;

use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn get(state: State<'_, AppState>) -> AppResult<HashMap<String, String>> {
    let rows = sqlx::query_as::<_, (String, String)>("SELECT action, content FROM prompts")
        .fetch_all(&state.pool().await?)
        .await?;

    Ok(rows.into_iter().collect())
}
