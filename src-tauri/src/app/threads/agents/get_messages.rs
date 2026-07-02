use tauri::State;

use crate::app::chat::message::{get_messages as load_messages, Message};
use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn get_messages(
    thread_id: String,
    state: State<'_, AppState>,
) -> AppResult<Vec<Message>> {
    load_messages(&thread_id, &state.pool().await?).await
}
