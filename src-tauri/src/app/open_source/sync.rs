use chrono::Utc;
use tauri::State;

use crate::state::AppState;

use super::models::OssSyncResultDto;
use super::summary;

pub async fn sync_contributions(
    state: State<'_, AppState>,
) -> Result<OssSyncResultDto, String> {
    let now = Utc::now().to_rfc3339();

    sqlx::query(
        "UPDATE github_contribution_profiles SET last_synced_at = ? WHERE id = (
            SELECT id FROM github_contribution_profiles ORDER BY created_at DESC LIMIT 1
         )",
    )
    .bind(&now)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let summary = summary::fetch_summary(state).await?;

    Ok(OssSyncResultDto {
        synced: summary.connected,
        last_synced_at: Some(now),
        repositories: summary.totals.repositories,
        pull_requests: summary.totals.pull_requests,
        issues: summary.totals.issues,
        reviews: summary.totals.reviews,
    })
}
