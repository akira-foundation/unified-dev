use tauri::{AppHandle, State};

use crate::app::autopilot;
use crate::app::autopilot::dto::{
    AutopilotJobDto, DeleteThreadRequest, SaveJobRequest, SaveThreadRequest, UpdateJobRequest,
    UpdateThreadRequest, WriteLogRequest,
};
use crate::app::support::error::AppError;
use crate::state::AppState;

async fn require_feature(
    state: &State<'_, AppState>,
    _app: &AppHandle,
    feature: &str,
    fallback_limit_code: &str,
) -> Result<(), String> {
    match crate::app::license::access::require_feature(state, feature).await {
        Ok(_) => Ok(()),
        Err(AppError::FreeTierLimit(_)) => {
            Err(AppError::FreeTierLimit(fallback_limit_code.to_string()).to_string())
        }
        Err(e) => Err(e.to_string()),
    }
}

#[tauri::command]
pub async fn autopilot_list_jobs(
    state: State<'_, AppState>,
) -> Result<Vec<AutopilotJobDto>, String> {
    autopilot::list_jobs(&state.pool().await.map_err(|e| e.to_string())?).await
}

#[tauri::command]
pub async fn autopilot_save_job(
    state: State<'_, AppState>,
    app: AppHandle,
    input: SaveJobRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    autopilot::save_job(&state.pool().await.map_err(|e| e.to_string())?, input).await
}

#[tauri::command]
pub async fn autopilot_update_job(
    state: State<'_, AppState>,
    app: AppHandle,
    input: UpdateJobRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    let status = input.status.clone();
    let job_id = input.id.clone();
    let total = input.total;
    autopilot::update_job(&state.pool().await.map_err(|e| e.to_string())?, input).await?;

    let (severity, title) = match status.as_str() {
        "completed" => (
            crate::app::notifications::NotificationSeverity::Success,
            "Autopilot job completed".to_string(),
        ),
        "failed" => (
            crate::app::notifications::NotificationSeverity::Error,
            "Autopilot job failed".to_string(),
        ),
        _ => return Ok(()),
    };

    let _ = crate::app::notifications::notify(
        &app,
        crate::app::notifications::NotificationInput {
            category: crate::app::notifications::NotificationCategory::Autopilot,
            severity,
            title,
            body: total.map(|t| format!("{t} issues processed")),
            action_type: Some("autopilot.open".to_string()),
            action_payload: Some(job_id),
            ttl_days: Some(7),
        },
    )
    .await;

    Ok(())
}

#[tauri::command]
pub async fn autopilot_save_thread(
    state: State<'_, AppState>,
    app: AppHandle,
    input: SaveThreadRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    autopilot::save_thread(&state.pool().await.map_err(|e| e.to_string())?, input).await
}

#[tauri::command]
pub async fn autopilot_update_thread(
    state: State<'_, AppState>,
    app: AppHandle,
    input: UpdateThreadRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    autopilot::update_thread(&state.pool().await.map_err(|e| e.to_string())?, input).await
}

#[tauri::command]
pub async fn autopilot_delete_job(
    state: State<'_, AppState>,
    job_id: String,
) -> Result<(), String> {
    autopilot::delete_job(&state.pool().await.map_err(|e| e.to_string())?, job_id).await
}

#[tauri::command]
pub async fn autopilot_delete_thread(
    state: State<'_, AppState>,
    input: DeleteThreadRequest,
) -> Result<(), String> {
    autopilot::delete_thread(
        &state.pool().await.map_err(|e| e.to_string())?,
        input.thread_row_id,
    )
    .await
}

#[tauri::command]
pub async fn autopilot_write_log(
    state: State<'_, AppState>,
    app: AppHandle,
    input: WriteLogRequest,
) -> Result<(), String> {
    require_feature(&state, &app, "autopilot", "autopilot_requires_pro").await?;
    autopilot::write_log(&state.pool().await.map_err(|e| e.to_string())?, input).await
}
