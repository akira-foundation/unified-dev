use sqlx::Row;
use tauri::State;

use crate::state::AppState;

use super::mocks;
use super::models::*;

pub async fn list_issues(
    state: State<'_, AppState>,
    filters: OssFiltersDto,
) -> Result<Vec<OssIssueDto>, String> {
    let rows = sqlx::query(
        "SELECT id, repo_id, name_with_owner, number, title, state, url,
                comments_count, created_at, closed_at
         FROM github_issues_oss
         ORDER BY created_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let items = if rows.is_empty() {
        mocks::issues()
    } else {
        rows.into_iter()
            .map(|row| OssIssueDto {
                id: row.try_get("id").unwrap_or_default(),
                repo_id: row.try_get("repo_id").unwrap_or_default(),
                name_with_owner: row.try_get("name_with_owner").unwrap_or_default(),
                number: row.try_get::<i64, _>("number").unwrap_or(0),
                title: row.try_get("title").unwrap_or_default(),
                state: row.try_get("state").unwrap_or_default(),
                url: row.try_get("url").unwrap_or_default(),
                comments_count: row.try_get::<i64, _>("comments_count").unwrap_or(0),
                created_at: row.try_get("created_at").unwrap_or_default(),
                closed_at: row.try_get("closed_at").ok(),
            })
            .collect()
    };

    Ok(items
        .into_iter()
        .filter(|i| match &filters.repo {
            Some(repo) if !repo.is_empty() => i.name_with_owner.to_lowercase().contains(&repo.to_lowercase()),
            _ => true,
        })
        .filter(|i| match &filters.state {
            Some(state) if !state.is_empty() => i.state.eq_ignore_ascii_case(state),
            _ => true,
        })
        .filter(|i| match filters.year {
            Some(year) => i.created_at.starts_with(&year.to_string()),
            None => true,
        })
        .collect())
}
