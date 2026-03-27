use tauri::{AppHandle, State};

use crate::app::chat::session;
use crate::app::chat::stream::emit_error;
use crate::state::AppState;
use crate::app::support::error::AppResult;

pub async fn send_message(
    thread_id: String,
    message: String,
    model: String,
    silent: Option<bool>,
    plan_mode: Option<bool>,
    thinking_budget: Option<String>,
    fast_mode: Option<bool>,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    let pool = state.db_pool.clone();
    let app = app.clone();
    let thread_id_err = thread_id.clone();
    let thread_id_map = thread_id.clone();
    let silent = silent.unwrap_or(false);
    let plan_mode = plan_mode.unwrap_or(false);
    let thinking_budget = thinking_budget.unwrap_or_else(|| "medium".to_string());
    let fast_mode = fast_mode.unwrap_or(false);
    let abort_handles = state.abort_handles.clone();

    let handle = tokio::spawn(async move {
        if let Err(e) = session::run(
            thread_id, message, model, silent,
            plan_mode, thinking_budget, fast_mode,
            pool, app.clone(),
        ).await {
            emit_error(&app, &thread_id_err, &e.to_string());
        }
    });

    if let Ok(mut map) = abort_handles.lock() {
        map.insert(thread_id_map, handle);
    }

    Ok(())
}
