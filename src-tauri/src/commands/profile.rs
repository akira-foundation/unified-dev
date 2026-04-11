use tauri::State;

use crate::app::profile;
use crate::app::profile::types::UserProfileDto;
use crate::app::support::error::AppResult;
use crate::state::AppState;

#[tauri::command]
pub async fn get_user_profile(state: State<'_, AppState>) -> AppResult<Option<UserProfileDto>> {
    profile::get(&state.db_pool).await
}

#[tauri::command]
pub async fn set_user_profile(email: String, state: State<'_, AppState>) -> AppResult<UserProfileDto> {
    profile::set(&email, &state.db_pool).await
}
