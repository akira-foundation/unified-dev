use tauri::State;

use crate::app::autopilot;
use crate::app::autopilot::dto::{
    AutopilotJobDto, DeleteThreadRequest, SaveJobRequest, SaveThreadRequest, UpdateJobRequest, UpdateThreadRequest,
    WriteLogRequest,
};
use crate::state::AppState;

#[tauri::command]
pub async fn autopilot_list_jobs(state: State<'_, AppState>) -> Result<Vec<AutopilotJobDto>, String> {
    autopilot::list_jobs(&state.db_pool).await
}

#[tauri::command]
pub async fn autopilot_save_job(
    state: State<'_, AppState>,
    input: SaveJobRequest,
) -> Result<(), String> {
    autopilot::save_job(&state.db_pool, input).await
}

#[tauri::command]
pub async fn autopilot_update_job(
    state: State<'_, AppState>,
    input: UpdateJobRequest,
) -> Result<(), String> {
    autopilot::update_job(&state.db_pool, input).await
}

#[tauri::command]
pub async fn autopilot_save_thread(
    state: State<'_, AppState>,
    input: SaveThreadRequest,
) -> Result<(), String> {
    autopilot::save_thread(&state.db_pool, input).await
}

#[tauri::command]
pub async fn autopilot_update_thread(
    state: State<'_, AppState>,
    input: UpdateThreadRequest,
) -> Result<(), String> {
    autopilot::update_thread(&state.db_pool, input).await
}

#[tauri::command]
pub async fn autopilot_delete_job(
    state: State<'_, AppState>,
    job_id: String,
) -> Result<(), String> {
    autopilot::delete_job(&state.db_pool, job_id).await
}

#[tauri::command]
pub async fn autopilot_delete_thread(
    state: State<'_, AppState>,
    input: DeleteThreadRequest,
) -> Result<(), String> {
    autopilot::delete_thread(&state.db_pool, input.thread_row_id).await
}

#[tauri::command]
pub async fn autopilot_write_log(
    state: State<'_, AppState>,
    input: WriteLogRequest,
) -> Result<(), String> {
    autopilot::write_log(&state.db_pool, input).await
}
