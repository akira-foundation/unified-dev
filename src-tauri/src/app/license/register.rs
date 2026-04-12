use crate::app::support::error::{AppError, AppResult};

use super::hmac;
use super::machine_id;
use super::types::{LicenseDto, WorkerLicenseResponse};

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");

pub async fn register(token: String, pool: &sqlx::SqlitePool, app: &tauri::AppHandle) -> AppResult<LicenseDto> {
    let identity = machine_id::get_or_create(app)?;

    let client = reqwest::Client::new();
    let res = client
        .post(format!("{AKIRA_API_URL}/billing/verify"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({
            "token": token,
            "machine_id": identity.id,
        }))
        .send()
        .await
        .map_err(AppError::Http)?;

    if !res.status().is_success() {
        let status = res.status().as_u16();
        let msg = res.text().await.unwrap_or_default();
        let error_code = serde_json::from_str::<serde_json::Value>(&msg)
            .ok()
            .and_then(|v| v["error"].as_str().map(str::to_string))
            .unwrap_or_else(|| msg.clone());

        return match status {
            403 => Err(AppError::Internal("device_limit_reached".into())),
            402 => Err(AppError::Internal("license_expired".into())),
            404 => Err(AppError::Internal("license_not_found".into())),
            _ => Err(AppError::Internal(format!("Registration failed: {error_code}"))),
        };
    }

    let worker_res: WorkerLicenseResponse = res.json().await.map_err(AppError::Http)?;

    if !hmac::verify(
        &worker_res.token,
        &worker_res.plan,
        &worker_res.cycle,
        &worker_res.valid_until,
        &worker_res.email,
        &worker_res.signature,
    ) {
        return Err(AppError::Internal("License signature verification failed".into()));
    }

    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO license (id, token, plan, cycle, email, status, valid_until, activated_at, last_verified_at, signature)
         VALUES ('local', ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           token = excluded.token,
           plan = excluded.plan,
           cycle = excluded.cycle,
           email = excluded.email,
           status = excluded.status,
           valid_until = excluded.valid_until,
           activated_at = excluded.activated_at,
           last_verified_at = excluded.last_verified_at,
           signature = excluded.signature",
    )
    .bind(&worker_res.token)
    .bind(&worker_res.plan)
    .bind(&worker_res.cycle)
    .bind(&worker_res.email)
    .bind(&worker_res.status)
    .bind(&worker_res.valid_until)
    .bind(&worker_res.activated_at)
    .bind(&now)
    .bind(&worker_res.signature)
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
        signature: worker_res.signature,
        grace_period: false,
        cancel_at_period_end: None,
        cancel_at: None,
        target_plan: None,
    })
}
