use crate::app::support::error::AppResult;

use super::types::{LicenseDto, WorkerStatusResponse};

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");

pub async fn get(pool: &sqlx::SqlitePool) -> AppResult<Option<LicenseDto>> {
    let row = sqlx::query_as::<_, LicenseDto>(
        "SELECT token, plan, cycle, email, status, valid_until, activated_at, last_verified_at
         FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

pub async fn verify(pool: &sqlx::SqlitePool) -> AppResult<Option<LicenseDto>> {
    let cached = get(pool).await?;
    let Some(license) = cached else {
        return Ok(None);
    };

    let last_verified = chrono::DateTime::parse_from_rfc3339(&license.last_verified_at)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .unwrap_or(chrono::DateTime::<chrono::Utc>::MIN_UTC);

    let age = chrono::Utc::now().signed_duration_since(last_verified);
    if age.num_days() < 7 {
        return Ok(Some(license));
    }

    let client = reqwest::Client::new();
    let res = client
        .get(format!("{AKIRA_API_URL}/billing/status"))
        .query(&[("token", &license.token)])
        .send()
        .await;

    let Ok(res) = res else {
        return Ok(Some(license));
    };

    if !res.status().is_success() {
        return Ok(Some(license));
    }

    let Ok(status_res) = res.json::<WorkerStatusResponse>().await else {
        return Ok(Some(license));
    };

    let now = chrono::Utc::now().to_rfc3339();
    let new_status = if status_res.valid { "active" } else { "expired" };

    sqlx::query(
        "UPDATE license SET status = ?, valid_until = COALESCE(?, valid_until), last_verified_at = ? WHERE id = 'local'",
    )
    .bind(new_status)
    .bind(status_res.valid_until.as_deref())
    .bind(&now)
    .execute(pool)
    .await?;

    get(pool).await
}

pub async fn clear(pool: &sqlx::SqlitePool) -> AppResult<()> {
    sqlx::query("DELETE FROM license WHERE id = 'local'")
        .execute(pool)
        .await?;
    Ok(())
}
