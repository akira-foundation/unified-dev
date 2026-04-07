use crate::app::support::error::AppResult;

use super::hmac;
use super::types::{LicenseDto, WorkerStatusResponse};

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");
const GRACE_PERIOD_DAYS: i64 = 5;

pub async fn get(pool: &sqlx::SqlitePool) -> AppResult<Option<LicenseDto>> {
    let row = sqlx::query_as::<_, LicenseDto>(
        "SELECT token, plan, cycle, email, status, valid_until, activated_at, last_verified_at, signature, 0 as grace_period
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

    // Verify HMAC integrity — reject tampered local data
    if !hmac::verify(
        &license.token,
        &license.plan,
        &license.cycle,
        &license.valid_until,
        &license.email,
        &license.signature,
    ) {
        clear(pool).await?;
        return Ok(None);
    }

    let valid_until = chrono::DateTime::parse_from_rfc3339(&license.valid_until)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .unwrap_or(chrono::DateTime::<chrono::Utc>::MIN_UTC);

    let now = chrono::Utc::now();

    // Layer 1 — valid_until not yet passed: trust local cache
    if now < valid_until {
        let last_verified = chrono::DateTime::parse_from_rfc3339(&license.last_verified_at)
            .map(|dt| dt.with_timezone(&chrono::Utc))
            .unwrap_or(chrono::DateTime::<chrono::Utc>::MIN_UTC);

        // Refresh from server every 7 days while still valid
        if now.signed_duration_since(last_verified).num_days() < 7 {
            return Ok(Some(license));
        }

        return refresh_from_server(pool, license).await;
    }

    // Layer 2 — valid_until passed: try to verify online first
    let refreshed = refresh_from_server(pool, license.clone()).await?;
    if let Some(ref l) = refreshed {
        // Online verification succeeded — return updated license
        if l.status == "active" {
            return Ok(refreshed);
        }
    }

    // Offline or expired online — check grace period
    let last_verified = chrono::DateTime::parse_from_rfc3339(&license.last_verified_at)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .unwrap_or(chrono::DateTime::<chrono::Utc>::MIN_UTC);

    let days_since_verified = now.signed_duration_since(last_verified).num_days();

    if days_since_verified < GRACE_PERIOD_DAYS {
        return Ok(Some(LicenseDto { grace_period: true, ..license }));
    }

    Ok(None)
}

async fn refresh_from_server(pool: &sqlx::SqlitePool, license: LicenseDto) -> AppResult<Option<LicenseDto>> {
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

    let new_signature = status_res.signature.unwrap_or_else(|| license.signature.clone());
    let new_valid_until = status_res.valid_until.as_deref().unwrap_or(&license.valid_until).to_string();
    let new_status = if status_res.valid { "active" } else { "expired" };
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "UPDATE license SET status = ?, valid_until = COALESCE(?, valid_until), last_verified_at = ?, signature = ? WHERE id = 'local'",
    )
    .bind(new_status)
    .bind(status_res.valid_until.as_deref())
    .bind(&now)
    .bind(&new_signature)
    .execute(pool)
    .await?;

    Ok(Some(LicenseDto {
        status: new_status.to_string(),
        valid_until: new_valid_until,
        last_verified_at: now,
        signature: new_signature,
        grace_period: false,
        ..license
    }))
}

pub async fn clear(pool: &sqlx::SqlitePool) -> AppResult<()> {
    sqlx::query("DELETE FROM license WHERE id = 'local'")
        .execute(pool)
        .await?;
    Ok(())
}
