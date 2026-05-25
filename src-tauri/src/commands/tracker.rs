use tauri::State;

use crate::app::tracker;
use crate::state::AppState;
use crate::tracker::dto::{TrackerIssue, TrackerIssueFilter, TrackerNamed};

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
