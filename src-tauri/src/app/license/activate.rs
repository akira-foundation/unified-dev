use akira_billing::types::LicenseActivatePayload;
use tauri::State;

use crate::app::billing::PRODUCT_SLUG;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

use super::machine_id;
use super::signed_license::{Keyring, SignedLicenseEnvelope};
use super::types::{ActivateLicenseRequest, LicenseDto};

pub async fn activate(
    input: ActivateLicenseRequest,
    state: State<'_, AppState>,
    app: &tauri::AppHandle,
) -> AppResult<LicenseDto> {
    let identity = machine_id::get_or_create(app)?;
    let platform = std::env::consts::OS;
    let app_version = env!("CARGO_PKG_VERSION");
    let device_name = input.device_name.as_deref();

    let response = {
        let billing = state.billing.read().await;
        billing
            .inner()
            .license_activate(LicenseActivatePayload {
                product: PRODUCT_SLUG,
                device_type: "desktop",
                platform: Some(platform),
                device_name,
                app_version: Some(app_version),
                fingerprint: &identity.id,
            })
            .await
            .map_err(|e| translate_billing_error(e, "license_activate"))?
    };

    let envelope = SignedLicenseEnvelope {
        key_id: response.license.key_id.clone(),
        algorithm: response.license.algorithm.clone(),
        payload: response.license.payload.clone(),
        signature: response.license.signature.clone(),
    };

    let keyring = Keyring::from_build_env()?;
    let payload = keyring.verify(&envelope)?;

    if payload.fingerprint_hash != identity.id {
        return Err(AppError::Internal(format!(
            "license fingerprint mismatch: payload={} device={}",
            payload.fingerprint_hash, identity.id
        )));
    }

    let now = chrono::Utc::now().to_rfc3339();
    let features_json = serde_json::to_string(&response.features).unwrap_or_default();

    sqlx::query(
        "UPDATE license SET
            plan = ?, status = ?, valid_until = ?, activated_at = ?,
            last_verified_at = ?, license_key_id = ?, license_algorithm = ?,
            license_payload = ?, license_signature = ?, features_json = ?,
            device_id = ?
         WHERE id = 'local'",
    )
    .bind(&response.plan)
    .bind("active")
    .bind(&payload.valid_until)
    .bind(&payload.issued_at)
    .bind(&now)
    .bind(&envelope.key_id)
    .bind(&envelope.algorithm)
    .bind(&envelope.payload)
    .bind(&envelope.signature)
    .bind(&features_json)
    .bind(&response.device.id)
    .execute(&state.db_pool)
    .await?;

    Ok(LicenseDto {
        token: String::new(),
        plan: response.plan,
        cycle: String::new(),
        email: payload.customer_id,
        status: "active".to_string(),
        valid_until: payload.valid_until,
        activated_at: payload.issued_at,
        last_verified_at: now,
        signature: envelope.signature,
        grace_period: false,
        cancel_at_period_end: None,
        cancel_at: None,
        target_plan: None,
    })
}

fn translate_billing_error(err: akira_billing::Error, context: &str) -> AppError {
    use akira_billing::Error as BErr;
    match err {
        BErr::Api { status, code } => {
            if !code.is_empty() {
                AppError::Internal(code)
            } else {
                AppError::Internal(format!("billing {context} failed: HTTP {status}"))
            }
        }
        other => AppError::Internal(format!("billing {context}: {other}")),
    }
}
