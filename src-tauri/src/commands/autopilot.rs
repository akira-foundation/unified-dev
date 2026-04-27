use tauri::{AppHandle, State};

use crate::app::autopilot;
use crate::app::autopilot::dto::{
    AutopilotJobDto, DeleteThreadRequest, SaveJobRequest, SaveThreadRequest, UpdateJobRequest, UpdateThreadRequest,
    WriteLogRequest,
};
use crate::app::support::error::AppError;
use crate::state::AppState;

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");

async fn require_feature(
    state: &State<'_, AppState>,
    app: &AppHandle,
    feature: &str,
    fallback_limit_code: &str,
) -> Result<(), String> {
    let plan_local = crate::app::license::get_plan(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    if plan_local == "pro" || plan_local == "ultimate" {
        return Ok(());
    }

    let token = crate::app::license::get_token(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?
        .unwrap_or_default();

    let identity = crate::app::license::machine_id::get_or_create(app)
        .map_err(|e| e.to_string())?;

    let client = reqwest::Client::new();
    let res = client
        .post(format!("{AKIRA_API_URL}/billing/feature_check"))
        .json(&serde_json::json!({
            "machine_id": identity.id,
            "token": token,
            "feature": feature,
            "created_at_sig": identity.created_at_sig,
        }))
        .send()
        .await
        .map_err(|e| e.to_string())?;

    let body: serde_json::Value = res.json().await.map_err(|e| e.to_string())?;

    if body["allowed"].as_bool() != Some(true) {
        return Err(AppError::FreeTierLimit(fallback_limit_code.to_string()).to_string());
    }
    Ok(())
}

#[tauri::command]
pub async fn autopilot_list_jobs(state: State<'_, AppState>) -> Result<Vec<AutopilotJobDto>, String> {
    autopilot::list_jobs(&state.db_pool).await
}

#[tauri::command]
pub async fn autopilot_save_job(
    state: State<'_, AppState>,
    app: AppHandle,
    input: SaveJobRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    autopilot::save_job(&state.db_pool, input).await
}

#[tauri::command]
pub async fn autopilot_update_job(
    state: State<'_, AppState>,
    app: AppHandle,
    input: UpdateJobRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    autopilot::update_job(&state.db_pool, input).await
}

#[tauri::command]
pub async fn autopilot_save_thread(
    state: State<'_, AppState>,
    app: AppHandle,
    input: SaveThreadRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    autopilot::save_thread(&state.db_pool, input).await
}

#[tauri::command]
pub async fn autopilot_update_thread(
    state: State<'_, AppState>,
    app: AppHandle,
    input: UpdateThreadRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
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
    app: AppHandle,
    input: WriteLogRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    autopilot::write_log(&state.db_pool, input).await
}
