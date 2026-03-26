use std::collections::HashMap;

use tauri::State;

use crate::app::prompts;
use crate::state::AppState;
use crate::support::error::AppResult;

#[tauri::command]
pub async fn get_prompts(state: State<'_, AppState>) -> AppResult<HashMap<String, String>> {
    prompts::get_prompts(state).await
}

#[tauri::command]
pub async fn save_prompt(action: String, content: String, state: State<'_, AppState>) -> AppResult<()> {
    prompts::save_prompt(action, content, state).await
}

#[tauri::command]
pub async fn reset_prompt(action: String, state: State<'_, AppState>) -> AppResult<()> {
    prompts::reset_prompt(action, state).await
}
