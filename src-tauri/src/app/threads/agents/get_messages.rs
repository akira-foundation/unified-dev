use tauri::State;

use crate::app::chat::message::{get_messages as load_messages, Message};
use crate::state::AppState;
use crate::app::support::error::AppResult;

pub async fn get_messages(thread_id: String, state: State<'_, AppState>) -> AppResult<Vec<Message>> {
    load_messages(&thread_id, &state.db_pool).await
}
