use akira_billing::license::decode_license;
use akira_billing::types::SignedLicense;
use chrono::Utc;

use crate::app::billing::{BillingClient, PRODUCT_SLUG};
use crate::app::support::error::AppResult;

use super::persist::load_envelope;
use super::signed_license::{refresh_public_keys, verify_envelope, SignedLicenseEnvelope};

pub async fn ensure_free_envelope(
    pool: &sqlx::SqlitePool,
    billing: &BillingClient,
) -> AppResult<()> {
    if load_envelope(pool).await?.is_some() {
        return Ok(());
    }

    let response = match billing.inner().public_free_snapshot(PRODUCT_SLUG).await {
        Ok(response) => response,
        Err(_) => return Ok(()),
    };

    let _ = refresh_public_keys(pool, billing.inner()).await?;

    let envelope = SignedLicenseEnvelope {
        key_id: response.license.key_id.clone(),
        algorithm: response.license.algorithm.clone(),
        payload: response.license.payload.clone(),
        signature: response.license.signature.clone(),
    };

    if verify_envelope(pool, &envelope).await.is_err() {
        return Ok(());
    }

    let signed = SignedLicense {
        key_id: response.license.key_id,
        algorithm: response.license.algorithm,
        payload: response.license.payload,
        signature: response.license.signature,
        valid_until: response.license.valid_until.clone(),
    };
    let decoded = match decode_license(&signed) {
        Ok(decoded) => decoded,
        Err(_) => return Ok(()),
    };

    let now = Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO license (
            id, token, plan, cycle, email, status, valid_until, activated_at,
            last_verified_at, signature,
            license_key_id, license_algorithm, license_payload, license_signature, features_json
         )
         VALUES ('local', '', 'free', '', '', 'active', ?, ?, ?, '', ?, ?, ?, ?, '{}')
         ON CONFLICT(id) DO UPDATE SET
            plan = 'free', cycle = '', status = 'active',
            valid_until = excluded.valid_until,
            activated_at = excluded.activated_at,
            last_verified_at = excluded.last_verified_at,
            license_key_id = excluded.license_key_id,
            license_algorithm = excluded.license_algorithm,
            license_payload = excluded.license_payload,
            license_signature = excluded.license_signature,
            features_json = excluded.features_json",
    )
    .bind(&decoded.payload.valid_until)
    .bind(&decoded.payload.issued_at)
    .bind(&now)
    .bind(&signed.key_id)
    .bind(&signed.algorithm)
    .bind(&signed.payload)
    .bind(&signed.signature)
    .execute(pool)
    .await?;

    Ok(())
}
