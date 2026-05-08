use chrono::Datelike;
use sqlx::Row;
use tauri::State;

use crate::state::AppState;

use super::models::*;

pub async fn fetch_summary(state: State<'_, AppState>) -> Result<ContributionSummaryDto, String> {
    let row = sqlx::query(
        "SELECT id, login, name, avatar_url, bio, followers, following,
                total_contributions, current_streak, best_streak,
                most_active_language, most_active_repo, last_synced_at, contribution_years,
                total_commits_period, total_prs_period, total_issues_period, total_reviews_period
         FROM github_contribution_profiles ORDER BY created_at DESC LIMIT 1",
    )
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let Some(row) = row else {
        return Err("github_not_synced".to_string());
    };

    let profile_id: String = row.try_get("id").map_err(|e| e.to_string())?;

    let profile = OssProfileDto {
        login: row.try_get("login").unwrap_or_default(),
        name: row.try_get("name").ok(),
        avatar_url: row.try_get("avatar_url").ok(),
        bio: row.try_get("bio").ok(),
        followers: row.try_get::<i64, _>("followers").unwrap_or(0),
        following: row.try_get::<i64, _>("following").unwrap_or(0),
    };

    let totals = aggregate_totals(&state, &profile_id).await?;
    let period_commits: i64 = row.try_get("total_commits_period").unwrap_or(0);
    let period_prs: i64 = row.try_get("total_prs_period").unwrap_or(0);
    let period_issues: i64 = row.try_get("total_issues_period").unwrap_or(0);
    let period_reviews: i64 = row.try_get("total_reviews_period").unwrap_or(0);

    let streaks = OssStreaksDto {
        current: row.try_get::<i64, _>("current_streak").unwrap_or(0),
        best: row.try_get::<i64, _>("best_streak").unwrap_or(0),
    };

    let years = row
        .try_get::<String, _>("contribution_years")
        .ok()
        .and_then(|s| serde_json::from_str::<Vec<i32>>(&s).ok())
        .filter(|v| !v.is_empty());
    let years = match years {
        Some(mut v) => {
            v.sort_unstable_by(|a, b| b.cmp(a));
            v
        }
        None => fetch_years(&state, &profile_id).await?,
    };
    let organizations_list = fetch_organizations(&state, &profile_id).await?;
    let (preview, repos_total) = fetch_repos_preview(&state, &profile_id).await?;
    let activity_breakdown =
        compute_breakdown(period_commits, period_prs, period_issues, period_reviews);

    Ok(ContributionSummaryDto {
        profile,
        totals,
        streaks,
        most_active_language: row.try_get("most_active_language").ok(),
        most_active_repo: row.try_get("most_active_repo").ok(),
        last_synced_at: row.try_get("last_synced_at").ok(),
        connected: true,
        years,
        organizations_list,
        activity_breakdown,
        contributed_repos_preview: preview,
        contributed_repos_total: repos_total,
    })
}

async fn aggregate_totals(
    state: &State<'_, AppState>,
    profile_id: &str,
) -> Result<OssTotalsDto, String> {
    async fn count_for_profile(
        pool: &sqlx::SqlitePool,
        sql: &str,
        profile_id: &str,
    ) -> Result<i64, String> {
        sqlx::query_scalar::<_, i64>(sql)
            .bind(profile_id)
            .fetch_one(pool)
            .await
            .map_err(|e| e.to_string())
    }

    let pool = &state.db_pool;
    let repositories = count_for_profile(
        pool,
        "SELECT COUNT(*) FROM github_contributed_repositories WHERE profile_id = ?",
        profile_id,
    )
    .await?;
    let pull_requests = count_for_profile(
        pool,
        "SELECT COUNT(*) FROM github_pull_requests_oss WHERE profile_id = ?",
        profile_id,
    )
    .await?;
    let merged_pull_requests = count_for_profile(
        pool,
        "SELECT COUNT(*) FROM github_pull_requests_oss WHERE profile_id = ? AND merged = 1",
        profile_id,
    )
    .await?;
    let issues = count_for_profile(
        pool,
        "SELECT COUNT(*) FROM github_issues_oss WHERE profile_id = ?",
        profile_id,
    )
    .await?;
    let reviews = count_for_profile(
        pool,
        "SELECT COUNT(*) FROM github_reviews_oss WHERE profile_id = ?",
        profile_id,
    )
    .await?;
    let organizations = count_for_profile(
        pool,
        "SELECT COUNT(DISTINCT owner_login) FROM github_contributed_repositories WHERE profile_id = ?",
        profile_id,
    )
    .await?;
    let commits_sum = sqlx::query_scalar::<_, Option<i64>>(
        "SELECT SUM(contributions_count) FROM github_contribution_snapshots WHERE profile_id = ?",
    )
    .bind(profile_id)
    .fetch_one(pool)
    .await
    .map_err(|e| e.to_string())?
    .unwrap_or(0);

    Ok(OssTotalsDto {
        repositories,
        pull_requests,
        merged_pull_requests,
        commits: commits_sum,
        issues,
        reviews,
        organizations,
    })
}

async fn fetch_years(
    state: &State<'_, AppState>,
    profile_id: &str,
) -> Result<Vec<i32>, String> {
    let rows = sqlx::query(
        "SELECT DISTINCT CAST(substr(day, 1, 4) AS INTEGER) AS year
         FROM github_contribution_snapshots
         WHERE profile_id = ?
         ORDER BY year DESC",
    )
    .bind(profile_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let mut years: Vec<i32> = rows
        .into_iter()
        .filter_map(|r| r.try_get::<i32, _>("year").ok())
        .collect();

    if years.is_empty() {
        years.push(chrono::Utc::now().date_naive().year());
    }
    Ok(years)
}

async fn fetch_organizations(
    state: &State<'_, AppState>,
    profile_id: &str,
) -> Result<Vec<OssOrgSummaryDto>, String> {
    let rows = sqlx::query(
        "SELECT owner_login, MAX(owner_avatar_url) AS avatar_url, MAX(owner_url) AS url
         FROM github_contributed_repositories
         WHERE profile_id = ?
         GROUP BY owner_login
         ORDER BY COUNT(*) DESC
         LIMIT 12",
    )
    .bind(profile_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(rows
        .into_iter()
        .map(|r| OssOrgSummaryDto {
            login: r.try_get("owner_login").unwrap_or_default(),
            avatar_url: r.try_get("avatar_url").ok(),
            url: r
                .try_get::<String, _>("url")
                .unwrap_or_else(|_| format!("https://github.com/{}", r.try_get::<String, _>("owner_login").unwrap_or_default())),
        })
        .collect())
}

async fn fetch_repos_preview(
    state: &State<'_, AppState>,
    profile_id: &str,
) -> Result<(Vec<String>, i64), String> {
    let rows = sqlx::query(
        "SELECT name_with_owner FROM github_contributed_repositories
         WHERE profile_id = ?
         ORDER BY last_contribution_at IS NULL, last_contribution_at DESC
         LIMIT 3",
    )
    .bind(profile_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;
    let preview: Vec<String> = rows
        .into_iter()
        .filter_map(|r| r.try_get::<String, _>("name_with_owner").ok())
        .collect();

    let total: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM github_contributed_repositories WHERE profile_id = ?",
    )
    .bind(profile_id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok((preview, total))
}

fn compute_breakdown(commits: i64, prs: i64, issues: i64, reviews: i64) -> ActivityBreakdownDto {
    let denom = (commits + prs + issues + reviews) as f64;
    if denom <= 0.0 {
        return ActivityBreakdownDto::default();
    }
    let pct = |n: i64| (n as f64 / denom) * 100.0;
    ActivityBreakdownDto {
        commits: pct(commits),
        pull_requests: pct(prs),
        issues: pct(issues),
        code_review: pct(reviews),
    }
}
