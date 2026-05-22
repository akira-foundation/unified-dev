use akira_billing::types::LicenseActivateResponse;

use crate::app::support::error::{AppError, AppResult};

use super::signed_license::{Keyring, SignedLicenseEnvelope};
use super::types::LicenseDto;

pub async fn store_activation(
    pool: &sqlx::SqlitePool,
    response: &LicenseActivateResponse,
    fingerprint: &str,
) -> AppResult<LicenseDto> {
    let envelope = SignedLicenseEnvelope {
        key_id: response.license.key_id.clone(),
        algorithm: response.license.algorithm.clone(),
        payload: response.license.payload.clone(),
        signature: response.license.signature.clone(),
    };

    let keyring = Keyring::from_build_env()?;
    let payload = keyring.verify(&envelope)?;

    if payload.fingerprint_hash != fingerprint {
        return Err(AppError::Internal(format!(
            "license fingerprint mismatch: payload={} device={}",
            payload.fingerprint_hash, fingerprint
        )));
    }

    let now = chrono::Utc::now().to_rfc3339();
    let features_json = serde_json::to_string(&response.features).unwrap_or_default();

    sqlx::query(
        "UPDATE license SET
            plan = ?, status = 'active', valid_until = ?, activated_at = ?,
            last_verified_at = ?, license_key_id = ?, license_algorithm = ?,
            license_payload = ?, license_signature = ?, features_json = ?,
            device_id = ?
         WHERE id = 'local'",
    )
    .bind(&response.plan)
    .bind(&payload.valid_until)
    .bind(&payload.issued_at)
    .bind(&now)
    .bind(&envelope.key_id)
    .bind(&envelope.algorithm)
    .bind(&envelope.payload)
    .bind(&envelope.signature)
    .bind(&features_json)
    .bind(&response.device.id)
    .execute(pool)
    .await?;

    Ok(LicenseDto {
        token: String::new(),
        plan: response.plan.clone(),
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

pub async fn load_envelope(pool: &sqlx::SqlitePool) -> AppResult<Option<SignedLicenseEnvelope>> {
    let row = sqlx::query_as::<_, (Option<String>, Option<String>, Option<String>, Option<String>)>(
        "SELECT license_key_id, license_algorithm, license_payload, license_signature
         FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?;

    let Some((Some(key_id), Some(algorithm), Some(payload), Some(signature))) = row else {
        return Ok(None);
    };

    if payload.is_empty() || signature.is_empty() {
        return Ok(None);
    }

    Ok(Some(SignedLicenseEnvelope {
        key_id,
        algorithm,
        payload,
        signature,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_license, setup_test_db};

    #[tokio::test]
    async fn load_envelope_returns_some_when_columns_present() {
        let pool = setup_test_db().await;
        seed_license(&pool, "pro", true).await;
        assert!(load_envelope(&pool).await.expect("load").is_some());
    }

    #[tokio::test]
    async fn load_envelope_returns_none_without_columns() {
        let pool = setup_test_db().await;
        seed_license(&pool, "free", false).await;
        assert!(load_envelope(&pool).await.expect("load").is_none());
    }
}
