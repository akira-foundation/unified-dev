use tauri::{AppHandle, State};

use crate::app::chat::stream::emit_done_aborted;
use crate::state::AppState;
use crate::app::support::error::AppResult;

pub async fn abort_agent(
    thread_id: String,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    if let Ok(mut map) = state.abort_handles.lock() {
        if let Some(handle) = map.remove(&thread_id) {
            handle.abort();
        }
    }

    emit_done_aborted(&app, &thread_id);

    Ok(())
}
