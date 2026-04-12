use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct LicenseDto {
    pub token: String,
    pub plan: String,
    pub cycle: String,
    pub email: String,
    pub status: String,
    pub valid_until: String,
    pub activated_at: String,
    pub last_verified_at: String,
    pub signature: String,
    pub grace_period: bool,
    pub cancel_at_period_end: Option<bool>,
    pub cancel_at: Option<String>,
    pub target_plan: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivateLicenseRequest {
    pub session_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckoutDto {
    pub url: String,
    pub session_id: String,
}

#[derive(Debug, Deserialize)]
pub struct WorkerLicenseResponse {
    pub token: String,
    pub plan: String,
    pub cycle: String,
    pub email: String,
    pub status: String,
    pub valid_until: String,
    pub activated_at: String,
    pub signature: String,
}

#[derive(Debug, Deserialize)]
pub struct WorkerStatusResponse {
    pub valid: bool,
    pub valid_until: Option<String>,
    pub signature: Option<String>,
    pub cancel_at_period_end: Option<bool>,
    pub cancel_at: Option<String>,
    pub target_plan: Option<String>,
}
