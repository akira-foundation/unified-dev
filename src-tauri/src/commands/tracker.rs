use tauri::State;

use crate::app::tracker;
use crate::state::AppState;
use crate::tracker::dto::{
    TrackerIssue, TrackerIssueDraft, TrackerIssueFilter, TrackerIssuePatch, TrackerNamed,
};

#[tauri::command]
pub async fn tracker_connect(
    state: State<'_, AppState>,
    provider: String,
    token: String,
) -> Result<TrackerNamed, String> {
    tracker::connect(&state, provider, token)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_status(
    state: State<'_, AppState>,
    provider: String,
) -> Result<bool, String> {
    tracker::status(&state, &provider)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_disconnect(
    state: State<'_, AppState>,
    provider: String,
) -> Result<(), String> {
    tracker::disconnect(&state, &provider)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_providers(state: State<'_, AppState>) -> Result<Vec<String>, String> {
    Ok(tracker::providers(&state))
}

#[tauri::command]
pub async fn tracker_sync(
    state: State<'_, AppState>,
    provider: String,
    filter: Option<TrackerIssueFilter>,
) -> Result<usize, String> {
    tracker::sync(&state, provider, filter.unwrap_or_default())
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_list_issues(
    state: State<'_, AppState>,
    provider: String,
) -> Result<Vec<TrackerIssue>, String> {
    tracker::list(&state, &provider)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_get_issue(
    state: State<'_, AppState>,
    id: String,
) -> Result<TrackerIssue, String> {
    tracker::get(&state, &id).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_create_issue(
    state: State<'_, AppState>,
    provider: String,
    draft: TrackerIssueDraft,
) -> Result<TrackerIssue, String> {
    tracker::create(&state, provider, draft)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_update_issue(
    state: State<'_, AppState>,
    provider: String,
    id: String,
    patch: TrackerIssuePatch,
) -> Result<TrackerIssue, String> {
    tracker::update(&state, provider, id, patch)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_close_issue(
    state: State<'_, AppState>,
    provider: String,
    id: String,
) -> Result<TrackerIssue, String> {
    tracker::close(&state, provider, id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_delete_issue(
    state: State<'_, AppState>,
    provider: String,
    id: String,
) -> Result<(), String> {
    tracker::delete(&state, provider, id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_list_projects(
    state: State<'_, AppState>,
    provider: String,
) -> Result<Vec<TrackerNamed>, String> {
    tracker::list_projects_named(&state, &provider)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn tracker_list_teams(
    state: State<'_, AppState>,
    provider: String,
) -> Result<Vec<TrackerNamed>, String> {
    tracker::list_teams_named(&state, &provider)
        .await
        .map_err(|e| e.to_string())
}
