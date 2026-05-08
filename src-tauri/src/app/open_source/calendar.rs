use sqlx::Row;
use tauri::State;

use crate::state::AppState;

use super::mocks;
use super::models::*;

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

    if rows.is_empty() {
        return Ok(mocks::calendar(target_year));
    }

    Ok(rows
        .into_iter()
        .map(|row| ContributionCalendarDayDto {
            date: row.try_get("day").unwrap_or_default(),
            count: row.try_get::<i64, _>("contributions_count").unwrap_or(0),
            color: row.try_get("color").ok(),
        })
        .collect())
}
