use crate::app::support::error::AppResult;

use super::hmac;
use super::types::{LicenseDto, WorkerStatusResponse};

const AKIRA_API_URL: &str = env!("AKIRA_BILLING_URL");
const GRACE_PERIOD_DAYS: i64 = 5;

pub async fn get_plan(pool: &sqlx::SqlitePool) -> AppResult<String> {
    let plan = sqlx::query_scalar::<_, String>(
        "SELECT plan FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?
    .filter(|p| !p.is_empty())
    .unwrap_or_else(|| "free".to_string());
    Ok(plan)
}

pub async fn get_token(pool: &sqlx::SqlitePool) -> AppResult<Option<String>> {
    Ok(sqlx::query_scalar::<_, String>(
        "SELECT token FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?)
}

pub async fn load_customer_token(
    pool: &sqlx::SqlitePool,
    cipher: &crate::app::support::security::TokenCipher,
) -> AppResult<Option<String>> {
    let cipher_blob = sqlx::query_scalar::<_, Option<String>>(
        "SELECT customer_token_cipher FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?
    .flatten();

    let Some(blob) = cipher_blob else {
        return Ok(None);
    };
    if blob.is_empty() {
        return Ok(None);
    }

    Ok(Some(cipher.decrypt(&blob)?))
}

pub async fn get(pool: &sqlx::SqlitePool) -> AppResult<Option<LicenseDto>> {
    let row = sqlx::query_as::<_, LicenseDto>(
        "SELECT token, plan, cycle, email, status, valid_until, activated_at, last_verified_at, signature, 0 as grace_period,
                CASE WHEN cancel_at_period_end = 1 THEN 1 ELSE 0 END as cancel_at_period_end,
                cancel_at, target_plan
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

    if license.token.is_empty() {
        return Ok(Some(license));
    }

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

    // Always refresh from server on explicit verify — no 7-day cache
    let refreshed = refresh_from_server(pool, license.clone()).await?;

    if let Some(ref l) = refreshed {
        if l.status == "active" {
            return Ok(refreshed);
        }
    }

    let last_verified = chrono::DateTime::parse_from_rfc3339(&license.last_verified_at)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .unwrap_or(chrono::DateTime::<chrono::Utc>::MIN_UTC);

    let days_since_verified = chrono::Utc::now().signed_duration_since(last_verified).num_days();

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
        if res.status() == reqwest::StatusCode::NOT_FOUND {
            clear(pool).await?;
            return Ok(None);
        }
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
        "UPDATE license SET status = ?, valid_until = COALESCE(?, valid_until), last_verified_at = ?, signature = ?,
                cancel_at_period_end = COALESCE(?, cancel_at_period_end), cancel_at = COALESCE(?, cancel_at), target_plan = COALESCE(?, target_plan)
         WHERE id = 'local'",
    )
    .bind(new_status)
    .bind(status_res.valid_until.as_deref())
    .bind(&now)
    .bind(&new_signature)
    .bind(status_res.cancel_at_period_end)
    .bind(status_res.cancel_at.as_deref())
    .bind(status_res.target_plan.as_deref())
    .execute(pool)
    .await?;

    Ok(Some(LicenseDto {
        status: new_status.to_string(),
        valid_until: new_valid_until,
        last_verified_at: now,
        signature: new_signature,
        grace_period: false,
        cancel_at_period_end: status_res.cancel_at_period_end.or(license.cancel_at_period_end),
        cancel_at: status_res.cancel_at.or(license.cancel_at),
        target_plan: status_res.target_plan.or(license.target_plan),
        ..license
    }))
}

pub async fn clear(pool: &sqlx::SqlitePool) -> AppResult<()> {
    sqlx::query("DELETE FROM license WHERE id = 'local'")
        .execute(pool)
        .await?;
    Ok(())
}
