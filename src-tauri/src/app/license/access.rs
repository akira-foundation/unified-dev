use akira_billing::gate::{DenyReason, FeatureAccess};

use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

pub async fn check_feature(state: &AppState, feature: &str) -> AppResult<FeatureAccess> {
    state
        .license_gate
        .check(feature)
        .await
        .map_err(|e| AppError::Internal(format!("license gate: {e}")))
}

pub async fn require_feature(state: &AppState, feature: &str) -> AppResult<FeatureAccess> {
    let access = check_feature(state, feature).await?;
    if access.allowed {
        return Ok(access);
    }
    Err(AppError::FreeTierLimit(deny_code(&access, feature)))
}

pub fn deny_code(access: &FeatureAccess, feature: &str) -> String {
    let kind = match access.reason_kind {
        Some(kind) => kind,
        None => return format!("{feature}_limit_reached"),
    };
    match (kind, feature) {
        (DenyReason::LicenseExpired | DenyReason::LicenseInvalid, _) => "license_expired".to_string(),
        (DenyReason::FeatureDisabled | DenyReason::FeatureMissing, "autopilot") => {
            "autopilot_requires_pro".to_string()
        }
        (DenyReason::FeatureDisabled | DenyReason::FeatureMissing, "remote_devices") => {
            "remote_requires_ultimate".to_string()
        }
        (DenyReason::FeatureDisabled | DenyReason::FeatureMissing, _) => {
            format!("{feature}_requires_pro")
        }
        (DenyReason::LimitReached, _) => format!("{}_limit_reached", limit_alias(feature)),
        (DenyReason::NoLicense, _) => format!("{}_limit_reached", limit_alias(feature)),
        _ => format!("{}_limit_reached", limit_alias(feature)),
    }
}

fn limit_alias(feature: &str) -> &str {
    match feature {
        "repos" => "repo",
        "orgs" => "org",
        "threads" => "thread",
        "runs_per_day" | "agent_runs" => "run",
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use akira_billing::lifecycle::LicenseState;

    fn access_with(reason: Option<DenyReason>) -> FeatureAccess {
        FeatureAccess {
            feature: "repos".to_string(),
            allowed: false,
            has_feature: false,
            unlimited: false,
            remaining: 0,
            reason: String::new(),
            reason_kind: reason,
            plan: String::new(),
            state: LicenseState::None,
        }
    }

    #[test]
    fn maps_limit_reached_to_repo_limit_reached() {
        let access = access_with(Some(DenyReason::LimitReached));
        assert_eq!(deny_code(&access, "repos"), "repo_limit_reached");
    }

    #[test]
    fn maps_expired_state_to_license_expired() {
        let access = access_with(Some(DenyReason::LicenseExpired));
        assert_eq!(deny_code(&access, "repos"), "license_expired");
    }

    #[test]
    fn maps_feature_disabled_to_autopilot_requires_pro() {
        let access = access_with(Some(DenyReason::FeatureDisabled));
        assert_eq!(deny_code(&access, "autopilot"), "autopilot_requires_pro");
    }

    #[test]
    fn maps_feature_disabled_to_remote_requires_ultimate() {
        let access = access_with(Some(DenyReason::FeatureDisabled));
        assert_eq!(deny_code(&access, "remote_devices"), "remote_requires_ultimate");
    }
}
