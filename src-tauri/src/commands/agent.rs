use tauri::{AppHandle, State};

use crate::app::chat::message::Message;
use crate::app::threads;
use crate::state::AppState;
use crate::app::support::error::AppResult;

#[tauri::command]
pub async fn get_available_models() -> Result<crate::ai::agents::registry::ModelRegistry, String> {
    threads::agents::get_available_models::get_available_models().await
}

#[tauri::command]
pub async fn abort_agent(thread_id: String, state: State<'_, AppState>, app: AppHandle) -> AppResult<()> {
    threads::agents::abort_agent::abort_agent(thread_id, state, app).await
}

#[tauri::command]
pub async fn get_messages(thread_id: String, state: State<'_, AppState>) -> AppResult<Vec<Message>> {
    threads::agents::get_messages::get_messages(thread_id, state).await
}

#[tauri::command]
pub async fn send_message(
    thread_id: String,
    message: String,
    model: String,
    silent: Option<bool>,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    threads::agents::send_message::send_message(thread_id, message, model, silent, state, app).await
}
