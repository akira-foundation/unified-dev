use serde_json::json;
use sqlx::Row;
use tauri::State;

use crate::state::AppState;

use super::graphql::{ContributionsData, CONTRIBUTIONS_QUERY};
use super::models::*;
use super::provider::find_github_driver;

pub async fn fetch_calendar(
    state: State<'_, AppState>,
    year: Option<i32>,
) -> Result<Vec<ContributionCalendarDayDto>, String> {
    let target_year = year.unwrap_or_else(|| chrono::Utc::now().date_naive().format("%Y").to_string().parse().unwrap_or(2025));

    let from = format!("{}-01-01", target_year);
    let to = format!("{}-12-31", target_year);

    let rows = sqlx::query(
        "SELECT day, contributions_count, color
         FROM github_contribution_snapshots
         WHERE day BETWEEN ? AND ?
         ORDER BY day ASC",
    )
    .bind(&from)
    .bind(&to)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    if !rows.is_empty() {
        return Ok(rows
            .into_iter()
            .map(|row| ContributionCalendarDayDto {
                date: row.try_get("day").unwrap_or_default(),
                count: row.try_get::<i64, _>("contributions_count").unwrap_or(0),
                color: row.try_get("color").ok(),
            })
            .collect());
    }

    fetch_year_from_github(&state, target_year).await
}

async fn fetch_year_from_github(
    state: &State<'_, AppState>,
    target_year: i32,
) -> Result<Vec<ContributionCalendarDayDto>, String> {
    let ctx = find_github_driver(state).await?;
    let from = format!("{}-01-01T00:00:00Z", target_year);
    let to = format!("{}-12-31T23:59:59Z", target_year);

    let data: ContributionsData = ctx
        .driver
        .graphql(CONTRIBUTIONS_QUERY, json!({ "from": from, "to": to }))
        .await
        .map_err(|e| e.to_string())?;

    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    let profile_row = sqlx::query("SELECT id FROM github_contribution_profiles WHERE customer_id = ? ORDER BY created_at DESC LIMIT 1")
        .bind(customer_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    let profile_id: Option<String> = profile_row.and_then(|r| r.try_get("id").ok());

    let mut out = Vec::new();
    for week in data.viewer.contributions_collection.contribution_calendar.weeks {
        for day in week.contribution_days {
            if let Some(pid) = profile_id.as_deref() {
                let _ = sqlx::query(
                    "INSERT INTO github_contribution_snapshots (profile_id, day, contributions_count, color)
                     VALUES (?, ?, ?, ?)
                     ON CONFLICT(profile_id, day) DO UPDATE SET
                        contributions_count = excluded.contributions_count,
                        color = excluded.color",
                )
                .bind(pid)
                .bind(&day.date)
                .bind(day.contribution_count)
                .bind(&day.color)
                .execute(&state.db_pool)
                .await;
            }
            out.push(ContributionCalendarDayDto {
                date: day.date,
                count: day.contribution_count,
                color: day.color,
            });
        }
    }
    Ok(out)
}
