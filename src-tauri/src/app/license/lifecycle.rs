use akira_billing::lifecycle::{compute_state, grace_days_left, trial_days_left, LicenseState};
use akira_billing::types::LicenseSnapshotPayload;
use chrono::{DateTime, Duration, Utc};

use crate::app::support::error::AppResult;

use super::persist::load_envelope;
use super::signed_license::verify_envelope;

const DEFAULT_OFFLINE_GRACE_DAYS: i64 = 7;

pub fn payload_grace_window(payload: &LicenseSnapshotPayload) -> Duration {
    let days = payload
        .offline_grace_days
        .map(|d| d as i64)
        .unwrap_or(DEFAULT_OFFLINE_GRACE_DAYS);
    Duration::days(days)
}

pub async fn load_payload(pool: &sqlx::SqlitePool) -> AppResult<Option<LicenseSnapshotPayload>> {
    let Some(envelope) = load_envelope(pool).await? else {
        return Ok(None);
    };
    Ok(verify_envelope(pool, &envelope).await.ok())
}

pub async fn current_state(pool: &sqlx::SqlitePool) -> AppResult<LicenseState> {
    let payload = load_payload(pool).await?;
    Ok(state_for(payload.as_ref(), Utc::now()))
}

pub fn state_for(payload: Option<&LicenseSnapshotPayload>, now: DateTime<Utc>) -> LicenseState {
    let grace = payload.map(payload_grace_window).unwrap_or_else(|| Duration::days(DEFAULT_OFFLINE_GRACE_DAYS));
    compute_state(payload, grace, now)
}

#[allow(dead_code)]
pub async fn grace_days_remaining(pool: &sqlx::SqlitePool) -> AppResult<i64> {
    let payload = load_payload(pool).await?;
    Ok(grace_days_left(payload.as_ref(), Utc::now()))
}

#[allow(dead_code)]
pub async fn trial_days_remaining(pool: &sqlx::SqlitePool) -> AppResult<i64> {
    let payload = load_payload(pool).await?;
    Ok(trial_days_left(payload.as_ref(), Utc::now()))
}

pub fn state_label(state: LicenseState) -> &'static str {
    match state {
        LicenseState::None => "none",
        LicenseState::Invalid => "invalid",
        LicenseState::Active => "active",
        LicenseState::Trialing => "trialing",
        LicenseState::Grace => "grace",
        LicenseState::Expired => "expired",
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use akira_billing::types::LicenseSnapshotPayload;
    use std::collections::HashMap;

    fn payload(valid_until: &str, grace_days: Option<u32>) -> LicenseSnapshotPayload {
        LicenseSnapshotPayload {
            v: None,
            key_id: "k1".into(),
            customer_id: "c1".into(),
            product_key: "unified-dev".into(),
            plan_key: "pro_monthly".into(),
            licensing_mode: None,
            features: HashMap::new(),
            usage: HashMap::new(),
            fingerprint_hash: "fp".into(),
            serial: 0,
            issued_at: "2026-01-01T00:00:00+00:00".into(),
            valid_until: valid_until.into(),
            paid_up_until: None,
            fallback_release_date: None,
            updates_window_days: None,
            offline_grace_days: grace_days,
            device_limit: None,
            payment_status: None,
        }
    }

    #[test]
    fn payload_grace_window_uses_payload_days() {
        let p = payload("2099-01-01T00:00:00+00:00", Some(14));
        assert_eq!(payload_grace_window(&p), Duration::days(14));
    }

    #[test]
    fn payload_grace_window_falls_back_to_default() {
        let p = payload("2099-01-01T00:00:00+00:00", None);
        assert_eq!(payload_grace_window(&p), Duration::days(DEFAULT_OFFLINE_GRACE_DAYS));
    }

    #[test]
    fn state_for_returns_active_when_within_validity() {
        let p = payload("2099-01-01T00:00:00+00:00", Some(7));
        let now = DateTime::parse_from_rfc3339("2026-05-28T00:00:00+00:00").unwrap().with_timezone(&Utc);
        assert_eq!(state_for(Some(&p), now), LicenseState::Active);
    }

    #[test]
    fn state_for_returns_grace_when_within_grace_window() {
        let p = payload("2026-05-25T00:00:00+00:00", Some(7));
        let now = DateTime::parse_from_rfc3339("2026-05-28T00:00:00+00:00").unwrap().with_timezone(&Utc);
        assert_eq!(state_for(Some(&p), now), LicenseState::Grace);
    }

    #[test]
    fn state_for_returns_expired_past_grace_window() {
        let p = payload("2026-05-01T00:00:00+00:00", Some(7));
        let now = DateTime::parse_from_rfc3339("2026-05-28T00:00:00+00:00").unwrap().with_timezone(&Utc);
        assert_eq!(state_for(Some(&p), now), LicenseState::Expired);
    }

    #[test]
    fn state_for_respects_payload_offline_grace_days() {
        let p = payload("2026-05-01T00:00:00+00:00", Some(60));
        let now = DateTime::parse_from_rfc3339("2026-05-28T00:00:00+00:00").unwrap().with_timezone(&Utc);
        assert_eq!(state_for(Some(&p), now), LicenseState::Grace);
    }

    #[test]
    fn state_for_returns_none_without_payload() {
        let now = Utc::now();
        assert_eq!(state_for(None, now), LicenseState::None);
    }
}
