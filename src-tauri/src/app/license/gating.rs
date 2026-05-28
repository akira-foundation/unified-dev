use akira_billing::license::{compute_remaining, RemainingValue};
use akira_billing::lifecycle::LicenseState;
use akira_billing::types::LicenseSnapshotPayload;

use crate::app::support::error::AppResult;

use super::lifecycle;
use super::persist;
use super::signed_license::Keyring;

const FREE_REPOS_LIMIT: u64 = 3;
const FREE_ORGS_LIMIT: u64 = 1;
const FREE_THREADS_LIMIT: u64 = 3;

pub fn free_limit(feature: &str) -> u64 {
    match feature {
        "repos" => FREE_REPOS_LIMIT,
        "orgs" => FREE_ORGS_LIMIT,
        "threads" => FREE_THREADS_LIMIT,
        _ => 0,
    }
}

pub fn decide(payload: &LicenseSnapshotPayload, feature: &str, consumed: u64) -> bool {
    !matches!(
        compute_remaining(payload, feature, consumed),
        Some(RemainingValue::Finite(0))
    )
}

pub async fn can_add(pool: &sqlx::SqlitePool, feature: &str, current_count: i64) -> AppResult<bool> {
    let current = current_count.max(0) as u64;
    let state = lifecycle::current_state(pool).await?;
    if matches!(state, LicenseState::Expired | LicenseState::Invalid) {
        return Ok(current < free_limit(feature));
    }

    let Some(envelope) = persist::load_envelope(pool).await? else {
        return Ok(current < free_limit(feature));
    };

    let keyring = Keyring::from_cache(pool).await?;
    let payload = keyring.verify(&envelope)?;
    Ok(decide(&payload, feature, current))
}

#[cfg(test)]
mod tests {
    use super::*;
    use akira_billing::types::UsageFeatureState;
    use std::collections::HashMap;

    fn payload_with(feature: &str, state: UsageFeatureState) -> LicenseSnapshotPayload {
        let mut usage = HashMap::new();
        usage.insert(feature.to_string(), state);
        LicenseSnapshotPayload {
            v: None,
            key_id: "k1".to_string(),
            customer_id: "c1".to_string(),
            product_key: "unified-dev".to_string(),
            plan_key: "free".to_string(),
            licensing_mode: None,
            features: HashMap::new(),
            usage,
            fingerprint_hash: "fp".to_string(),
            serial: 0,
            issued_at: "2026-01-01T00:00:00+00:00".to_string(),
            valid_until: "2099-01-01T00:00:00+00:00".to_string(),
            paid_up_until: None,
            fallback_release_date: None,
            updates_window_days: None,
            offline_grace_days: None,
            device_limit: None,
        }
    }

    #[test]
    fn blocks_when_count_at_limit() {
        let payload = payload_with("repos", UsageFeatureState::Count { limit: Some(3) });
        assert!(decide(&payload, "repos", 2));
        assert!(!decide(&payload, "repos", 3));
        assert!(!decide(&payload, "repos", 4));
    }

    #[test]
    fn allows_when_unlimited_or_absent() {
        let unlimited = payload_with("repos", UsageFeatureState::Count { limit: None });
        assert!(decide(&unlimited, "repos", 999));
        assert!(decide(&unlimited, "orgs", 999));
    }

    #[test]
    fn free_limit_known_features() {
        assert_eq!(free_limit("repos"), FREE_REPOS_LIMIT);
        assert_eq!(free_limit("orgs"), FREE_ORGS_LIMIT);
        assert_eq!(free_limit("threads"), FREE_THREADS_LIMIT);
        assert_eq!(free_limit("autopilot"), 0);
    }

    #[tokio::test]
    async fn can_add_applies_free_limit_without_envelope() {
        let pool = crate::test_utils::setup_test_db().await;
        crate::test_utils::seed_license(&pool, "free", false).await;
        assert!(can_add(&pool, "repos", 2).await.expect("under limit"));
        assert!(!can_add(&pool, "repos", 3).await.expect("at limit"));
        assert!(!can_add(&pool, "repos", 4).await.expect("over limit"));
    }

    #[tokio::test]
    async fn can_add_blocks_unknown_feature_when_no_envelope() {
        let pool = crate::test_utils::setup_test_db().await;
        crate::test_utils::seed_license(&pool, "free", false).await;
        assert!(!can_add(&pool, "anything-else", 0).await.expect("unknown"));
    }
}
