use chrono::{Datelike, Utc};
use serde_json::json;
use sqlx::Row;
use tauri::State;

use crate::providers::drivers::github::client::GitHubDriver;
use crate::state::AppState;

use super::graphql::*;
use super::models::OssSyncResultDto;
use super::provider::find_github_driver;

pub async fn sync_contributions(state: State<'_, AppState>) -> Result<OssSyncResultDto, String> {
    let app_state: &AppState = &state;
    let ctx = find_github_driver(app_state).await?;
    let driver = &ctx.driver;
    let provider_id = ctx.provider_id.clone();
    let now = Utc::now();
    let now_iso = now.to_rfc3339();

    let viewer: ViewerData = driver
        .graphql(VIEWER_QUERY, json!({}))
        .await
        .map_err(|e| e.to_string())?;
    let v = viewer.viewer;

    let years_data: YearsData = driver
        .graphql(FIRST_CONTRIBUTION_YEAR_QUERY, json!({}))
        .await
        .map_err(|e| e.to_string())?;
    let mut years = years_data.viewer.contributions_collection.contribution_years;
    years.sort_unstable_by(|a, b| b.cmp(a));

    let current_year = now.year();
    let from = format!("{}-01-01T00:00:00Z", current_year);
    let to = format!("{}-12-31T23:59:59Z", current_year);

    let contribs: ContributionsData = driver
        .graphql(CONTRIBUTIONS_QUERY, json!({ "from": from, "to": to }))
        .await
        .map_err(|e| e.to_string())?;
    let cc = contribs.viewer.contributions_collection;

    let calendar_days: Vec<(String, i64, Option<String>)> = cc
        .contribution_calendar
        .weeks
        .iter()
        .flat_map(|w| w.contribution_days.iter())
        .map(|d| (d.date.clone(), d.contribution_count, d.color.clone()))
        .collect();

    let (current_streak, best_streak) = compute_streaks(&calendar_days);

    let most_active_repo = cc
        .commit_contributions_by_repository
        .first()
        .map(|r| r.repository.name_with_owner.clone());

    let profile_id = format!("github:{}", v.login);

    let years_json = serde_json::to_string(&years).unwrap_or_else(|_| "[]".to_string());
    sqlx::query(
        "INSERT INTO github_contribution_profiles
         (id, provider_id, login, name, avatar_url, bio, followers, following,
          total_contributions, current_streak, best_streak,
          most_active_language, most_active_repo, last_synced_at, created_at, contribution_years,
          total_commits_period, total_prs_period, total_issues_period, total_reviews_period)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
            provider_id = excluded.provider_id,
            name = excluded.name,
            avatar_url = excluded.avatar_url,
            bio = excluded.bio,
            followers = excluded.followers,
            following = excluded.following,
            total_contributions = excluded.total_contributions,
            current_streak = excluded.current_streak,
            best_streak = excluded.best_streak,
            most_active_repo = excluded.most_active_repo,
            last_synced_at = excluded.last_synced_at,
            contribution_years = excluded.contribution_years,
            total_commits_period = excluded.total_commits_period,
            total_prs_period = excluded.total_prs_period,
            total_issues_period = excluded.total_issues_period,
            total_reviews_period = excluded.total_reviews_period",
    )
    .bind(&profile_id)
    .bind(&provider_id)
    .bind(&v.login)
    .bind(&v.name)
    .bind(&v.avatar_url)
    .bind(&v.bio)
    .bind(v.followers.total_count)
    .bind(v.following.total_count)
    .bind(cc.contribution_calendar.total_contributions)
    .bind(current_streak)
    .bind(best_streak)
    .bind(&most_active_repo)
    .bind(&now_iso)
    .bind(&now_iso)
    .bind(&years_json)
    .bind(cc.total_commit_contributions)
    .bind(cc.total_pull_request_contributions)
    .bind(cc.total_issue_contributions)
    .bind(cc.total_pull_request_review_contributions)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    sqlx::query("DELETE FROM github_contribution_snapshots WHERE profile_id = ?")
        .bind(&profile_id)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    for (date, count, color) in &calendar_days {
        sqlx::query(
            "INSERT INTO github_contribution_snapshots (profile_id, day, contributions_count, color)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(profile_id, day) DO UPDATE SET
                contributions_count = excluded.contributions_count,
                color = excluded.color",
        )
        .bind(&profile_id)
        .bind(date)
        .bind(count)
        .bind(color)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    sqlx::query(
        "DELETE FROM github_contributed_repositories WHERE profile_id = ? AND LOWER(owner_login) = LOWER(?)",
    )
    .bind(&profile_id)
    .bind(&v.login)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let repo_count = sync_repositories(&state, driver, &profile_id, &v.login).await?;
    let pr_count = sync_pull_requests(&state, driver, &profile_id, &v.login).await?;
    let issue_count = sync_issues(&state, driver, &profile_id, &v.login).await?;
    let review_count = sync_reviews(&state, driver, &profile_id, &v.login, &from, &to).await?;
    backfill_years(&state, driver, &profile_id, &v.login, &years).await?;
    let (lifetime_current, lifetime_best) = compute_lifetime_streaks(&state, &profile_id).await?;
    let lifetime_total: i64 = sqlx::query_scalar(
        "SELECT COALESCE(SUM(contributions_count), 0) FROM github_contribution_snapshots WHERE profile_id = ?",
    )
    .bind(&profile_id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;
    sqlx::query(
        "UPDATE github_contribution_profiles SET current_streak = ?, best_streak = ?, total_contributions = ? WHERE id = ?",
    )
    .bind(lifetime_current)
    .bind(lifetime_best)
    .bind(lifetime_total)
    .bind(&profile_id)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let language = most_active_language(&state, &profile_id).await?;
    if language.is_some() {
        sqlx::query("UPDATE github_contribution_profiles SET most_active_language = ? WHERE id = ?")
            .bind(&language)
            .bind(&profile_id)
            .execute(&state.db_pool)
            .await
            .map_err(|e| e.to_string())?;
    }

    Ok(OssSyncResultDto {
        synced: true,
        last_synced_at: Some(now_iso),
        repositories: repo_count,
        pull_requests: pr_count,
        issues: issue_count,
        reviews: review_count,
    })
}

fn compute_streaks(days: &[(String, i64, Option<String>)]) -> (i64, i64) {
    let mut sorted: Vec<&(String, i64, Option<String>)> = days.iter().collect();
    sorted.sort_by(|a, b| a.0.cmp(&b.0));

    let mut best = 0i64;
    let mut run = 0i64;
    let mut current = 0i64;
    let today = Utc::now().date_naive().to_string();

    for entry in &sorted {
        if entry.1 > 0 {
            run += 1;
            best = best.max(run);
        } else {
            run = 0;
        }
    }

    for entry in sorted.iter().rev() {
        if entry.0 > today {
            continue;
        }
        if entry.1 > 0 {
            current += 1;
        } else {
            break;
        }
    }

    (current, best)
}

async fn sync_repositories(
    state: &State<'_, AppState>,
    driver: &GitHubDriver,
    profile_id: &str,
    viewer_login: &str,
) -> Result<i64, String> {
    let raw = driver
        .graphql_paginated::<Option<RepoNode>, _, ReposContributedData>(
            REPOS_CONTRIBUTED_QUERY,
            json!({}),
            |data| {
                let conn = data.viewer.repositories_contributed_to;
                let nodes = conn.nodes;
                let has_next = conn.page_info.has_next_page;
                (nodes, has_next, conn.page_info.end_cursor)
            },
        )
        .await
        .map_err(|e| e.to_string())?;
    let nodes: Vec<RepoNode> = raw
        .into_iter()
        .flatten()
        .filter(|n| !n.owner.login.eq_ignore_ascii_case(viewer_login))
        .collect();

    sqlx::query("DELETE FROM github_contributed_repositories WHERE profile_id = ?")
        .bind(profile_id)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    for node in &nodes {
        sqlx::query(
            "INSERT INTO github_contributed_repositories
             (id, profile_id, name_with_owner, owner_login, description, primary_language,
              stars, forks, url, is_fork, is_archived, last_contribution_at,
              owner_avatar_url, owner_url)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&node.id)
        .bind(profile_id)
        .bind(&node.name_with_owner)
        .bind(&node.owner.login)
        .bind(&node.description)
        .bind(node.primary_language.as_ref().map(|l| l.name.clone()))
        .bind(node.stargazer_count)
        .bind(node.fork_count)
        .bind(&node.url)
        .bind(node.is_fork as i64)
        .bind(node.is_archived as i64)
        .bind(&node.pushed_at)
        .bind(&node.owner.avatar_url)
        .bind(&node.owner.url)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    Ok(nodes.len() as i64)
}

async fn upsert_repo_from_simple(
    state: &State<'_, AppState>,
    profile_id: &str,
    viewer_login: &str,
    repo: &SimpleRepoRef,
) -> Result<(), String> {
    if repo.owner.login.eq_ignore_ascii_case(viewer_login) {
        return Ok(());
    }
    sqlx::query(
        "INSERT INTO github_contributed_repositories
         (id, profile_id, name_with_owner, owner_login, description, primary_language,
          stars, forks, url, is_fork, is_archived, last_contribution_at,
          owner_avatar_url, owner_url)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
            name_with_owner = excluded.name_with_owner,
            owner_login = excluded.owner_login,
            description = excluded.description,
            primary_language = excluded.primary_language,
            stars = excluded.stars,
            forks = excluded.forks,
            url = excluded.url,
            is_fork = excluded.is_fork,
            is_archived = excluded.is_archived,
            last_contribution_at = excluded.last_contribution_at,
            owner_avatar_url = excluded.owner_avatar_url,
            owner_url = excluded.owner_url",
    )
    .bind(&repo.id)
    .bind(profile_id)
    .bind(&repo.name_with_owner)
    .bind(&repo.owner.login)
    .bind(&repo.description)
    .bind(repo.primary_language.as_ref().map(|l| l.name.clone()))
    .bind(repo.stargazer_count)
    .bind(repo.fork_count)
    .bind(&repo.url)
    .bind(repo.is_fork as i64)
    .bind(repo.is_archived as i64)
    .bind(&repo.pushed_at)
    .bind(&repo.owner.avatar_url)
    .bind(&repo.owner.url)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;
    Ok(())
}

async fn sync_pull_requests(
    state: &State<'_, AppState>,
    driver: &GitHubDriver,
    profile_id: &str,
    viewer_login: &str,
) -> Result<i64, String> {
    let raw = driver
        .graphql_paginated::<Option<PrNode>, _, PullRequestsData>(
            PULL_REQUESTS_QUERY,
            json!({}),
            |data| {
                let conn = data.viewer.pull_requests;
                let nodes = conn.nodes;
                let has_next = conn.page_info.has_next_page;
                (nodes, has_next, conn.page_info.end_cursor)
            },
        )
        .await
        .map_err(|e| e.to_string())?;
    let nodes: Vec<PrNode> = raw.into_iter().flatten().collect();

    sqlx::query("DELETE FROM github_pull_requests_oss WHERE profile_id = ?")
        .bind(profile_id)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    for node in &nodes {
        upsert_repo_from_simple(state, profile_id, viewer_login, &node.repository).await?;
        sqlx::query(
            "INSERT INTO github_pull_requests_oss
             (id, profile_id, repo_id, name_with_owner, number, title, state, merged, url,
              additions, deletions, created_at, merged_at, closed_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&node.id)
        .bind(profile_id)
        .bind(&node.repository.id)
        .bind(&node.repository.name_with_owner)
        .bind(node.number)
        .bind(&node.title)
        .bind(&node.state)
        .bind(node.merged as i64)
        .bind(&node.url)
        .bind(node.additions)
        .bind(node.deletions)
        .bind(&node.created_at)
        .bind(&node.merged_at)
        .bind(&node.closed_at)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    Ok(nodes.len() as i64)
}

async fn sync_issues(
    state: &State<'_, AppState>,
    driver: &GitHubDriver,
    profile_id: &str,
    viewer_login: &str,
) -> Result<i64, String> {
    let raw = driver
        .graphql_paginated::<Option<IssueNode>, _, IssuesData>(
            ISSUES_QUERY,
            json!({}),
            |data| {
                let conn = data.viewer.issues;
                let nodes = conn.nodes;
                let has_next = conn.page_info.has_next_page;
                (nodes, has_next, conn.page_info.end_cursor)
            },
        )
        .await
        .map_err(|e| e.to_string())?;
    let nodes: Vec<IssueNode> = raw.into_iter().flatten().collect();

    sqlx::query("DELETE FROM github_issues_oss WHERE profile_id = ?")
        .bind(profile_id)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    for node in &nodes {
        upsert_repo_from_simple(state, profile_id, viewer_login, &node.repository).await?;
        sqlx::query(
            "INSERT INTO github_issues_oss
             (id, profile_id, repo_id, name_with_owner, number, title, state, url,
              comments_count, created_at, closed_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&node.id)
        .bind(profile_id)
        .bind(&node.repository.id)
        .bind(&node.repository.name_with_owner)
        .bind(node.number)
        .bind(&node.title)
        .bind(&node.state)
        .bind(&node.url)
        .bind(node.comments.total_count)
        .bind(&node.created_at)
        .bind(&node.closed_at)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    Ok(nodes.len() as i64)
}

async fn sync_reviews(
    state: &State<'_, AppState>,
    driver: &GitHubDriver,
    profile_id: &str,
    viewer_login: &str,
    from: &str,
    to: &str,
) -> Result<i64, String> {
    let data: ReviewsData = driver
        .graphql(REVIEWS_QUERY, json!({ "from": from, "to": to }))
        .await
        .map_err(|e| e.to_string())?;

    sqlx::query("DELETE FROM github_reviews_oss WHERE profile_id = ?")
        .bind(profile_id)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    let mut count = 0i64;
    for by_repo in data.viewer.contributions_collection.pull_request_review_contributions_by_repository {
        upsert_repo_from_simple(state, profile_id, viewer_login, &by_repo.repository).await?;
        for n in by_repo.contributions.nodes {
            let r = n.pull_request_review;
            sqlx::query(
                "INSERT INTO github_reviews_oss
                 (id, profile_id, repo_id, name_with_owner, pr_number, pr_title, state, url, submitted_at)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                 ON CONFLICT(id) DO UPDATE SET
                    state = excluded.state,
                    url = excluded.url,
                    submitted_at = excluded.submitted_at",
            )
            .bind(&r.id)
            .bind(profile_id)
            .bind(&by_repo.repository.id)
            .bind(&by_repo.repository.name_with_owner)
            .bind(r.pull_request.number)
            .bind(&r.pull_request.title)
            .bind(&r.state)
            .bind(&r.url)
            .bind(r.submitted_at.unwrap_or_default())
            .execute(&state.db_pool)
            .await
            .map_err(|e| e.to_string())?;
            count += 1;
        }
    }

    Ok(count)
}

async fn backfill_years(
    state: &State<'_, AppState>,
    driver: &GitHubDriver,
    profile_id: &str,
    viewer_login: &str,
    years: &[i32],
) -> Result<(), String> {
    for &year in years {
        let from = format!("{}-01-01T00:00:00Z", year);
        let to = format!("{}-12-31T23:59:59Z", year);
        let calendar_data: ContributionsData = match driver
            .graphql(CONTRIBUTIONS_QUERY, json!({ "from": from, "to": to }))
            .await
        {
            Ok(d) => d,
            Err(_) => continue,
        };
        for week in calendar_data.viewer.contributions_collection.contribution_calendar.weeks {
            for day in week.contribution_days {
                let _ = sqlx::query(
                    "INSERT INTO github_contribution_snapshots (profile_id, day, contributions_count, color)
                     VALUES (?, ?, ?, ?)
                     ON CONFLICT(profile_id, day) DO UPDATE SET
                        contributions_count = excluded.contributions_count,
                        color = excluded.color",
                )
                .bind(profile_id)
                .bind(&day.date)
                .bind(day.contribution_count)
                .bind(&day.color)
                .execute(&state.db_pool)
                .await;
            }
        }

        let data: YearOverviewData = match driver
            .graphql(YEAR_OVERVIEW_QUERY, json!({ "from": from, "to": to }))
            .await
        {
            Ok(d) => d,
            Err(_) => continue,
        };
        let cc = data.viewer.contributions_collection;
        let groups = [
            cc.commit_contributions_by_repository,
            cc.issue_contributions_by_repository,
            cc.pull_request_contributions_by_repository,
            cc.pull_request_review_contributions_by_repository,
        ];
        for group in groups {
            for entry in group {
                let r = &entry.repository;
                if r.owner.login.eq_ignore_ascii_case(viewer_login) {
                    continue;
                }
                let _ = sqlx::query(
                    "INSERT INTO github_contributed_repositories
                     (id, profile_id, name_with_owner, owner_login, description, primary_language,
                      stars, forks, url, is_fork, is_archived, last_contribution_at,
                      owner_avatar_url, owner_url)
                     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                     ON CONFLICT(id) DO UPDATE SET
                        name_with_owner = excluded.name_with_owner,
                        owner_login = excluded.owner_login,
                        description = excluded.description,
                        primary_language = excluded.primary_language,
                        stars = excluded.stars,
                        forks = excluded.forks,
                        url = excluded.url,
                        is_fork = excluded.is_fork,
                        is_archived = excluded.is_archived,
                        last_contribution_at = excluded.last_contribution_at,
                        owner_avatar_url = excluded.owner_avatar_url,
                        owner_url = excluded.owner_url",
                )
                .bind(&r.id)
                .bind(profile_id)
                .bind(&r.name_with_owner)
                .bind(&r.owner.login)
                .bind(&r.description)
                .bind(r.primary_language.as_ref().map(|l| l.name.clone()))
                .bind(r.stargazer_count)
                .bind(r.fork_count)
                .bind(&r.url)
                .bind(r.is_fork as i64)
                .bind(r.is_archived as i64)
                .bind(&r.pushed_at)
                .bind(&r.owner.avatar_url)
                .bind(&r.owner.url)
                .execute(&state.db_pool)
                .await;
            }
        }
    }
    Ok(())
}

async fn compute_lifetime_streaks(
    state: &State<'_, AppState>,
    profile_id: &str,
) -> Result<(i64, i64), String> {
    let rows = sqlx::query(
        "SELECT day, contributions_count FROM github_contribution_snapshots
         WHERE profile_id = ?
         ORDER BY day ASC",
    )
    .bind(profile_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let days: Vec<(String, i64)> = rows
        .into_iter()
        .map(|r| {
            let day: String = r.try_get("day").unwrap_or_default();
            let count: i64 = r.try_get("contributions_count").unwrap_or(0);
            (day, count)
        })
        .collect();

    let mut best = 0i64;
    let mut run = 0i64;
    for (_, count) in &days {
        if *count > 0 {
            run += 1;
            best = best.max(run);
        } else {
            run = 0;
        }
    }

    let today = Utc::now().date_naive().to_string();
    let mut current = 0i64;
    for (day, count) in days.iter().rev() {
        if day.as_str() > today.as_str() {
            continue;
        }
        if *count > 0 {
            current += 1;
        } else {
            break;
        }
    }
    Ok((current, best))
}

async fn most_active_language(
    state: &State<'_, AppState>,
    profile_id: &str,
) -> Result<Option<String>, String> {
    let row = sqlx::query(
        "SELECT primary_language, COUNT(*) as c
         FROM github_contributed_repositories
         WHERE profile_id = ? AND primary_language IS NOT NULL
         GROUP BY primary_language
         ORDER BY c DESC
         LIMIT 1",
    )
    .bind(profile_id)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(row.and_then(|r| r.try_get::<String, _>("primary_language").ok()))
}
