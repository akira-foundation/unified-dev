use crate::app::support::error::{AppError, AppResult};

use super::types::{ActivateLicenseRequest, LicenseDto, WorkerLicenseResponse};

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");

pub async fn activate(input: ActivateLicenseRequest, pool: &sqlx::SqlitePool) -> AppResult<LicenseDto> {
    let client = reqwest::Client::new();
    let res = client
        .post(format!("{AKIRA_API_URL}/billing/activate"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({ "session_id": input.session_id }))
        .send()
        .await
        .map_err(AppError::Http)?;

    if !res.status().is_success() {
        let msg = res.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("Activation failed: {msg}")));
    }

    let worker_res: WorkerLicenseResponse = res.json().await.map_err(AppError::Http)?;

    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO license (id, token, plan, cycle, email, status, valid_until, activated_at, last_verified_at)
         VALUES ('local', ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           token = excluded.token,
           plan = excluded.plan,
           cycle = excluded.cycle,
           email = excluded.email,
           status = excluded.status,
           valid_until = excluded.valid_until,
           activated_at = excluded.activated_at,
           last_verified_at = excluded.last_verified_at",
    )
    .bind(&worker_res.token)
    .bind(&worker_res.plan)
    .bind(&worker_res.cycle)
    .bind(&worker_res.email)
    .bind(&worker_res.status)
    .bind(&worker_res.valid_until)
    .bind(&worker_res.activated_at)
    .bind(&now)
    .execute(pool)
    .await?;

    Ok(LicenseDto {
        token: worker_res.token,
        plan: worker_res.plan,
        cycle: worker_res.cycle,
        email: worker_res.email,
        status: worker_res.status,
        valid_until: worker_res.valid_until,
        activated_at: worker_res.activated_at,
        last_verified_at: now,
    })
}
