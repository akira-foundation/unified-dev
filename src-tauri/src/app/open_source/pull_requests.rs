use sqlx::Row;
use tauri::State;

use crate::state::AppState;

use super::mocks;
use super::models::*;

pub async fn list_pull_requests(
    state: State<'_, AppState>,
    filters: OssFiltersDto,
) -> Result<Vec<OssPullRequestDto>, String> {
    let rows = sqlx::query(
        "SELECT id, repo_id, name_with_owner, number, title, state, merged, url,
                additions, deletions, created_at, merged_at, closed_at
         FROM github_pull_requests_oss
         ORDER BY created_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let prs = if rows.is_empty() {
        mocks::pull_requests()
    } else {
        rows.into_iter()
            .map(|row| OssPullRequestDto {
                id: row.try_get("id").unwrap_or_default(),
                repo_id: row.try_get("repo_id").unwrap_or_default(),
                name_with_owner: row.try_get("name_with_owner").unwrap_or_default(),
                number: row.try_get::<i64, _>("number").unwrap_or(0),
                title: row.try_get("title").unwrap_or_default(),
                state: row.try_get("state").unwrap_or_default(),
                merged: row.try_get::<i64, _>("merged").unwrap_or(0) != 0,
                url: row.try_get("url").unwrap_or_default(),
                additions: row.try_get::<i64, _>("additions").unwrap_or(0),
                deletions: row.try_get::<i64, _>("deletions").unwrap_or(0),
                created_at: row.try_get("created_at").unwrap_or_default(),
                merged_at: row.try_get("merged_at").ok(),
                closed_at: row.try_get("closed_at").ok(),
            })
            .collect()
    };

    Ok(apply_filters(prs, &filters))
}

fn apply_filters(items: Vec<OssPullRequestDto>, filters: &OssFiltersDto) -> Vec<OssPullRequestDto> {
    items
        .into_iter()
        .filter(|p| match &filters.repo {
            Some(repo) if !repo.is_empty() => p.name_with_owner.to_lowercase().contains(&repo.to_lowercase()),
            _ => true,
        })
        .filter(|p| match &filters.org {
            Some(org) if !org.is_empty() => p
                .name_with_owner
                .split('/')
                .next()
                .map(|o| o.eq_ignore_ascii_case(org))
                .unwrap_or(false),
            _ => true,
        })
        .filter(|p| match &filters.state {
            Some(state) if !state.is_empty() => match state.as_str() {
                "merged" => p.merged,
                "open" => p.state.eq_ignore_ascii_case("OPEN"),
                "closed" => p.state.eq_ignore_ascii_case("CLOSED") && !p.merged,
                _ => true,
            },
            _ => true,
        })
        .filter(|p| match filters.year {
            Some(year) => p.created_at.starts_with(&year.to_string()),
            None => true,
        })
        .collect()
}
