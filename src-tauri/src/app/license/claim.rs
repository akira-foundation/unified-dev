use akira_billing::types::{OtpRequestPayload, OtpVerifyPayload};
use tauri::State;

use crate::app::profile;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

use super::types::LicenseDto;

pub async fn request_otp(email: String, state: State<'_, AppState>) -> AppResult<()> {
    let fingerprint = super::device_fingerprint();
    let platform = onyx::osinfo::Platform::current().as_str();
    let app_version = env!("CARGO_PKG_VERSION");

    let billing = state.billing.read().await;
    billing
        .inner()
        .request_otp(OtpRequestPayload {
            email: &email,
            device_fp: Some(&fingerprint),
            platform: Some(platform),
            app_version: Some(app_version),
            product_key: Some("maintainer"),
        })
        .await
        .map_err(|e| translate_billing_error(e, "otp_request"))?;

    Ok(())
}

pub async fn verify_otp(
    email: String,
    otp: String,
    state: State<'_, AppState>,
) -> AppResult<LicenseDto> {
    let fingerprint = super::device_fingerprint();

    let response = {
        let mut billing = state.billing.write().await;
        billing
            .inner_mut()
            .verify_otp(OtpVerifyPayload {
                email: &email,
                code: &otp,
                device_fp: Some(&fingerprint),
            })
            .await
            .map_err(|e| translate_billing_error(e, "otp_verify"))?
    };

    let encrypted_token = state.token_cipher.encrypt(&response.access_token)?;
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO license (
            id, token, plan, cycle, email, status, valid_until, activated_at,
            last_verified_at, signature, customer_id, customer_email,
            customer_token_cipher
         )
         VALUES ('local', '', '', '', ?, 'pending', '', ?, ?, '', ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
            email = excluded.email,
            customer_id = excluded.customer_id,
            customer_email = excluded.customer_email,
            customer_token_cipher = excluded.customer_token_cipher,
            last_verified_at = excluded.last_verified_at",
    )
    .bind(&response.customer.email)
    .bind(&now)
    .bind(&now)
    .bind(&response.customer.id)
    .bind(&response.customer.email)
    .bind(&encrypted_token)
    .execute(&state.db_pool)
    .await?;

    let current_profile = profile::get(&state.db_pool).await.ok().flatten();
    let purchase_email = response.customer.email.clone();
    let should_update_profile = current_profile
        .map(|p| p.email != purchase_email)
        .unwrap_or(true);
    if should_update_profile {
        let _ = profile::set(&purchase_email, &state.db_pool).await;
    }

    Ok(LicenseDto {
        token: String::new(),
        plan: String::new(),
        cycle: String::new(),
        email: response.customer.email,
        status: "pending".to_string(),
        valid_until: String::new(),
        activated_at: now.clone(),
        last_verified_at: now,
        signature: String::new(),
        grace_period: false,
        cancel_at_period_end: None,
        cancel_at: None,
        target_plan: None,
        payment_status: None,
    })
}

fn translate_billing_error(err: akira_billing::Error, context: &str) -> AppError {
    use akira_billing::Error as BErr;
    match err {
        BErr::Api { status, code, .. } => {
            if !code.is_empty() {
                AppError::Internal(code)
            } else {
                AppError::Internal(format!("billing {context} failed: HTTP {status}"))
            }
        }
        other => AppError::Internal(format!("billing {context}: {other}")),
    }
}
