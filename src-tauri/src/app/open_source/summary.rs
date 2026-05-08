use sqlx::Row;
use tauri::State;

use crate::state::AppState;

use super::mocks;
use super::models::*;

pub async fn fetch_summary(state: State<'_, AppState>) -> Result<ContributionSummaryDto, String> {
    let row = sqlx::query(
        "SELECT login, name, avatar_url, bio, followers, following,
                total_contributions, current_streak, best_streak,
                most_active_language, most_active_repo, last_synced_at
         FROM github_contribution_profiles ORDER BY created_at DESC LIMIT 1",
    )
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let Some(row) = row else {
        let mut summary = mocks::summary();
        summary.connected = false;
        return Ok(summary);
    };

    let profile_login: String = row.try_get("login").map_err(|e| e.to_string())?;
    let profile = OssProfileDto {
        login: profile_login.clone(),
        name: row.try_get("name").ok(),
        avatar_url: row.try_get("avatar_url").ok(),
        bio: row.try_get("bio").ok(),
        followers: row.try_get::<i64, _>("followers").unwrap_or(0),
        following: row.try_get::<i64, _>("following").unwrap_or(0),
    };

    let totals = aggregate_totals(&state).await?;

    let streaks = OssStreaksDto {
        current: row.try_get::<i64, _>("current_streak").unwrap_or(0),
        best: row.try_get::<i64, _>("best_streak").unwrap_or(0),
    };

    Ok(ContributionSummaryDto {
        profile,
        totals,
        streaks,
        most_active_language: row.try_get("most_active_language").ok(),
        most_active_repo: row.try_get("most_active_repo").ok(),
        last_synced_at: row.try_get("last_synced_at").ok(),
        connected: true,
    })
}

async fn aggregate_totals(state: &State<'_, AppState>) -> Result<OssTotalsDto, String> {
    let pool = &state.db_pool;

    async fn count(pool: &sqlx::SqlitePool, sql: &str) -> Result<i64, String> {
        sqlx::query_scalar::<_, i64>(sql)
            .fetch_one(pool)
            .await
            .map_err(|e| e.to_string())
    }

    let repositories = count(pool, "SELECT COUNT(*) FROM github_contributed_repositories").await?;
    let pull_requests = count(pool, "SELECT COUNT(*) FROM github_pull_requests_oss").await?;
    let merged_pull_requests = count(pool, "SELECT COUNT(*) FROM github_pull_requests_oss WHERE merged = 1").await?;
    let issues = count(pool, "SELECT COUNT(*) FROM github_issues_oss").await?;
    let reviews = count(pool, "SELECT COUNT(*) FROM github_reviews_oss").await?;
    let commits = sqlx::query_scalar::<_, Option<i64>>("SELECT SUM(count) FROM github_commits_oss")
        .fetch_one(pool)
        .await
        .map_err(|e| e.to_string())?
        .unwrap_or(0);
    let organizations = count(pool, "SELECT COUNT(DISTINCT owner_login) FROM github_contributed_repositories").await?;

    Ok(OssTotalsDto {
        repositories,
        pull_requests,
        merged_pull_requests,
        commits,
        issues,
        reviews,
        organizations,
    })
}
