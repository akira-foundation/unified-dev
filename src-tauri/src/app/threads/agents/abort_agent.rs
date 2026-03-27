use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use tauri::{AppHandle, State};

use crate::app::chat::stream::emit_done_aborted;
use crate::state::AppState;
use crate::app::support::error::AppResult;
use tokio::task::JoinHandle;

pub async fn abort_agent_core(
    thread_id: String,
    abort_handles: Arc<Mutex<HashMap<String, JoinHandle<()>>>>,
    app: AppHandle,
) -> AppResult<()> {
    if let Ok(mut map) = abort_handles.lock() {
        if let Some(handle) = map.remove(&thread_id) {
            handle.abort();
        }
    }

    emit_done_aborted(&app, &thread_id);

    Ok(())
}

pub async fn abort_agent(
    thread_id: String,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    abort_agent_core(thread_id, state.abort_handles.clone(), app).await
}
