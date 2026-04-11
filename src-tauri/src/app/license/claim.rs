use crate::app::profile;
use crate::app::support::error::{AppError, AppResult};

use super::hmac;
use super::machine_id;
use super::types::{LicenseDto, WorkerClaimResponse};

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");

pub async fn request_otp(email: String) -> AppResult<()> {
    let client = reqwest::Client::new();
    let res = client
        .post(format!("{AKIRA_API_URL}/billing/claim/request"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({ "email": email }))
        .send()
        .await
        .map_err(AppError::Http)?;

    if res.status().as_u16() == 429 {
        let body = res.text().await.unwrap_or_default();
        let retry_after = serde_json::from_str::<serde_json::Value>(&body)
            .ok()
            .and_then(|v| v["retry_after"].as_u64())
            .unwrap_or(3600);
        return Err(AppError::Internal(format!("rate_limit_exceeded:{retry_after}")));
    }

    Ok(())
}

pub async fn verify_otp(
    email: String,
    otp: String,
    pool: &sqlx::SqlitePool,
    app: &tauri::AppHandle,
) -> AppResult<LicenseDto> {
    let identity = machine_id::get_or_create(app)?;

    let client = reqwest::Client::new();
    let res = client
        .post(format!("{AKIRA_API_URL}/billing/claim/verify"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({
            "email": email,
            "otp": otp,
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

        return match error_code.as_str() {
            "otp_expired" => Err(AppError::Internal("otp_expired".into())),
            "otp_invalid" => Err(AppError::Internal("otp_invalid".into())),
            "email_not_found" => Err(AppError::Internal("email_not_found".into())),
            "license_expired" => Err(AppError::Internal("license_expired".into())),
            "device_limit_reached" => Err(AppError::Internal("device_limit_reached".into())),
            _ => match status {
                403 => Err(AppError::Internal("device_limit_reached".into())),
                402 => Err(AppError::Internal("license_expired".into())),
                404 => Err(AppError::Internal("email_not_found".into())),
                _ => Err(AppError::Internal(format!("Claim verify failed: {error_code}"))),
            },
        };
    }

    let worker_res: WorkerClaimResponse = res.json().await.map_err(AppError::Http)?;

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

    let current_profile = profile::get(pool).await.ok().flatten();
    let purchase_email = worker_res.email.clone();
    let should_update_profile = current_profile
        .map(|p| p.email != purchase_email)
        .unwrap_or(true);

    if should_update_profile {
        let _ = profile::set(&purchase_email, pool).await;
    }

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
    })
}
