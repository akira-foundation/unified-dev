use akira_billing::desktop::VerifiedLicense;

use crate::app::support::error::{AppError, AppResult};

use super::signed_license::SignedLicenseEnvelope;
use super::types::LicenseDto;

pub fn split_plan_key(plan_key: &str) -> (String, String) {
    if let Some(tier) = plan_key.strip_suffix("_monthly") {
        return (tier.to_string(), "monthly".to_string());
    }
    if let Some(tier) = plan_key.strip_suffix("_yearly") {
        return (tier.to_string(), "yearly".to_string());
    }
    (plan_key.to_string(), String::new())
}

pub async fn store_verified(pool: &sqlx::SqlitePool, verified: &VerifiedLicense) -> AppResult<LicenseDto> {
    let (plan, cycle) = split_plan_key(&verified.plan);
    let now = chrono::Utc::now().to_rfc3339();
    let features_json = serde_json::to_string(&verified.features).unwrap_or_default();

    sqlx::query(
        "UPDATE license SET
            plan = ?, cycle = ?, status = 'active', valid_until = ?, activated_at = ?,
            last_verified_at = ?, license_key_id = ?, license_algorithm = ?,
            license_payload = ?, license_signature = ?, features_json = ?,
            device_id = ?
         WHERE id = 'local'",
    )
    .bind(&plan)
    .bind(&cycle)
    .bind(&verified.payload.valid_until)
    .bind(&verified.payload.issued_at)
    .bind(&now)
    .bind(&verified.signed.key_id)
    .bind(&verified.signed.algorithm)
    .bind(&verified.signed.payload)
    .bind(&verified.signed.signature)
    .bind(&features_json)
    .bind(&verified.device_id)
    .execute(pool)
    .await?;

    super::verify::get(pool)
        .await?
        .ok_or_else(|| AppError::Internal("license row missing after store_verified".into()))
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

    #[test]
    fn split_plan_key_separates_tier_and_cycle() {
        assert_eq!(split_plan_key("pro_monthly"), ("pro".to_string(), "monthly".to_string()));
        assert_eq!(split_plan_key("ultimate_yearly"), ("ultimate".to_string(), "yearly".to_string()));
        assert_eq!(split_plan_key("free"), ("free".to_string(), String::new()));
    }

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

    #[tokio::test]
    async fn store_verified_keeps_db_email_and_splits_plan() {
        use akira_billing::types::{LicenseSnapshotPayload, SignedLicense};
        use std::collections::HashMap;

        let pool = setup_test_db().await;
        seed_license(&pool, "free", false).await;

        let verified = VerifiedLicense {
            signed: SignedLicense {
                key_id: "k1".to_string(),
                algorithm: "ed25519".to_string(),
                payload: "cGF5".to_string(),
                signature: "c2ln".to_string(),
                valid_until: "2099-01-01T00:00:00+00:00".to_string(),
            },
            payload: LicenseSnapshotPayload {
                v: None,
                key_id: "k1".to_string(),
                customer_id: "019e2e53-cde8-7218".to_string(),
                product_key: "unified-dev".to_string(),
                plan_key: "pro_monthly".to_string(),
                licensing_mode: None,
                features: HashMap::new(),
                usage: HashMap::new(),
                fingerprint_hash: "fp".to_string(),
                serial: 0,
                issued_at: "2026-01-01T00:00:00+00:00".to_string(),
                valid_until: "2099-01-01T00:00:00+00:00".to_string(),
                paid_up_until: None,
                fallback_release_date: None,
                updates_window_days: None,
                offline_grace_days: None,
            },
            plan: "pro_monthly".to_string(),
            features: HashMap::new(),
            device_id: "dev1".to_string(),
        };

        let dto = store_verified(&pool, &verified).await.expect("store_verified");

        assert_eq!(dto.email, "a@b.c");
        assert_ne!(dto.email, verified.payload.customer_id);
        assert_eq!(dto.plan, "pro");
        assert_eq!(dto.cycle, "monthly");
        assert_eq!(dto.status, "active");
    }
}
