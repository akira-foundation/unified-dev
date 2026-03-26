use tauri::{AppHandle, State};

use crate::app::chat::session;
use crate::app::chat::stream::emit_error;
use crate::state::AppState;
use crate::support::error::AppResult;

pub async fn send_message(
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
