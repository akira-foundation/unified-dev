use tauri::{AppHandle, State};

use crate::chat::message::{get_messages, Message};
use crate::chat::session;
use crate::chat::stream::emit_error;
use crate::error::AppResult;
use crate::state::AppState;

/// Returns all persisted messages for a thread, oldest-first (capped at 40).
#[tauri::command]
pub async fn agents_get_messages(
    thread_id: String,
    state: State<'_, AppState>,
) -> AppResult<Vec<Message>> {
    get_messages(&thread_id, &state.db_pool).await
}

/// Saves the user message, streams the model response via Tauri events,
/// then saves the completed assistant response. Returns immediately — the
/// stream runs in a background task.
///
/// Frontend events emitted during the stream:
///   "agent-stream-token" → { thread_id, token }
///   "agent-stream-done"  → { thread_id }
///   "agent-stream-error" → { thread_id, error }
#[tauri::command]
pub async fn agents_send_message(
    thread_id: String,
    message: String,
    model: String,
    silent: Option<bool>,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    let pool = state.db_pool.clone();
    let app = app.clone();
    let thread_id_err = thread_id.clone();
    let silent = silent.unwrap_or(false);

    tokio::spawn(async move {
        if let Err(e) = session::run(thread_id, message, model, silent, pool, app.clone()).await {
            emit_error(&app, &thread_id_err, &e.to_string());
        }
    });

    Ok(())
}
