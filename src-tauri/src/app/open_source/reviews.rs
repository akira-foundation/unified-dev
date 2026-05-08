use sqlx::Row;
use tauri::State;

use crate::state::AppState;

use super::mocks;
use super::models::*;

pub async fn list_reviews(
    state: State<'_, AppState>,
    filters: OssFiltersDto,
) -> Result<Vec<OssReviewDto>, String> {
    let rows = sqlx::query(
        "SELECT id, repo_id, name_with_owner, pr_number, pr_title, state, url, submitted_at
         FROM github_reviews_oss
         ORDER BY submitted_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let items = if rows.is_empty() {
        mocks::reviews()
    } else {
        rows.into_iter()
            .map(|row| OssReviewDto {
                id: row.try_get("id").unwrap_or_default(),
                repo_id: row.try_get("repo_id").unwrap_or_default(),
                name_with_owner: row.try_get("name_with_owner").unwrap_or_default(),
                pr_number: row.try_get::<i64, _>("pr_number").unwrap_or(0),
                pr_title: row.try_get("pr_title").ok(),
                state: row.try_get("state").unwrap_or_default(),
                url: row.try_get("url").unwrap_or_default(),
                submitted_at: row.try_get("submitted_at").unwrap_or_default(),
            })
            .collect()
    };

    Ok(items
        .into_iter()
        .filter(|r| match &filters.repo {
            Some(repo) if !repo.is_empty() => r.name_with_owner.to_lowercase().contains(&repo.to_lowercase()),
            _ => true,
        })
        .filter(|r| match &filters.state {
            Some(state) if !state.is_empty() => r.state.eq_ignore_ascii_case(state),
            _ => true,
        })
        .filter(|r| match filters.year {
            Some(year) => r.submitted_at.starts_with(&year.to_string()),
            None => true,
        })
        .collect())
}
