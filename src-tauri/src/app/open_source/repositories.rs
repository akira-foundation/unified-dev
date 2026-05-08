use sqlx::Row;
use tauri::State;

use crate::state::AppState;

use super::models::*;

pub async fn list_repositories(
    state: State<'_, AppState>,
    filters: OssFiltersDto,
) -> Result<Vec<ContributedRepoDto>, String> {
    let rows = sqlx::query(
        "SELECT id, name_with_owner, owner_login, description, primary_language,
                stars, forks, url, is_fork, is_archived, last_contribution_at
         FROM github_contributed_repositories
         ORDER BY last_contribution_at IS NULL, last_contribution_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let repos = rows
        .into_iter()
        .map(|row| ContributedRepoDto {
            id: row.try_get("id").unwrap_or_default(),
            name_with_owner: row.try_get("name_with_owner").unwrap_or_default(),
            owner_login: row.try_get("owner_login").unwrap_or_default(),
            description: row.try_get("description").ok(),
            primary_language: row.try_get("primary_language").ok(),
            stars: row.try_get::<i64, _>("stars").unwrap_or(0),
            forks: row.try_get::<i64, _>("forks").unwrap_or(0),
            url: row.try_get("url").unwrap_or_default(),
            is_fork: row.try_get::<i64, _>("is_fork").unwrap_or(0) != 0,
            is_archived: row.try_get::<i64, _>("is_archived").unwrap_or(0) != 0,
            last_contribution_at: row.try_get("last_contribution_at").ok(),
        })
        .collect::<Vec<_>>();

    Ok(filter_repositories(repos, &filters))
}

fn filter_repositories(
    items: Vec<ContributedRepoDto>,
    filters: &OssFiltersDto,
) -> Vec<ContributedRepoDto> {
    items
        .into_iter()
        .filter(|r| match &filters.org {
            Some(org) if !org.is_empty() => r.owner_login.eq_ignore_ascii_case(org),
            _ => true,
        })
        .filter(|r| match &filters.repo {
            Some(repo) if !repo.is_empty() => r
                .name_with_owner
                .to_lowercase()
                .contains(&repo.to_lowercase()),
            _ => true,
        })
        .collect()
}
