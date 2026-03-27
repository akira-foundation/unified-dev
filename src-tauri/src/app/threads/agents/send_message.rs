use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use tauri::{AppHandle, State};

use crate::app::chat::session;
use crate::app::chat::stream::emit_error;
use crate::state::AppState;
use crate::app::support::error::AppResult;
use tokio::task::JoinHandle;

pub async fn spawn_send_message(
    thread_id: String,
    message: String,
    model: String,
    silent: Option<bool>,
    plan_mode: Option<bool>,
    thinking_budget: Option<String>,
    fast_mode: Option<bool>,
    pool: sqlx::SqlitePool,
    abort_handles: Arc<Mutex<HashMap<String, JoinHandle<()>>>>,
    app: AppHandle,
) -> AppResult<()> {
    let app = app.clone();
    let thread_id_err = thread_id.clone();
    let thread_id_map = thread_id.clone();
    let silent = silent.unwrap_or(false);
    let plan_mode = plan_mode.unwrap_or(false);
    let thinking_budget = thinking_budget.unwrap_or_else(|| "medium".to_string());
    let fast_mode = fast_mode.unwrap_or(false);

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
    spawn_send_message(
        thread_id,
        message,
        model,
        silent,
        plan_mode,
        thinking_budget,
        fast_mode,
        state.db_pool.clone(),
        state.abort_handles.clone(),
        app,
    ).await
}
