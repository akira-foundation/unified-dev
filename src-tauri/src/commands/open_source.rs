use tauri::State;

use crate::app::open_source;
use crate::app::open_source::models::*;
use crate::state::AppState;

#[tauri::command]
pub async fn fetch_github_contribution_summary(
    state: State<'_, AppState>,
) -> Result<ContributionSummaryDto, String> {
    open_source::fetch_summary(state).await
}

#[tauri::command]
pub async fn fetch_github_contributed_repositories(
    state: State<'_, AppState>,
    filters: Option<OssFiltersDto>,
) -> Result<Vec<ContributedRepoDto>, String> {
    open_source::list_repositories(state, filters.unwrap_or_default()).await
}

#[tauri::command]
pub async fn fetch_github_pull_requests(
    state: State<'_, AppState>,
    filters: Option<OssFiltersDto>,
) -> Result<Vec<OssPullRequestDto>, String> {
    open_source::list_pull_requests(state, filters.unwrap_or_default()).await
}

#[tauri::command]
pub async fn fetch_github_issues(
    state: State<'_, AppState>,
    filters: Option<OssFiltersDto>,
) -> Result<Vec<OssIssueDto>, String> {
    open_source::list_issues(state, filters.unwrap_or_default()).await
}

#[tauri::command]
pub async fn fetch_github_reviews(
    state: State<'_, AppState>,
    filters: Option<OssFiltersDto>,
) -> Result<Vec<OssReviewDto>, String> {
    open_source::list_reviews(state, filters.unwrap_or_default()).await
}

#[tauri::command]
pub async fn fetch_github_contribution_calendar(
    state: State<'_, AppState>,
    year: Option<i32>,
) -> Result<Vec<ContributionCalendarDayDto>, String> {
    open_source::fetch_calendar(state, year).await
}

#[tauri::command]
pub async fn sync_github_open_source_contributions(
    state: State<'_, AppState>,
) -> Result<OssSyncResultDto, String> {
    open_source::sync_contributions(state).await
}
