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
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ActivateLicenseRequest {
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
}

#[derive(Debug, Deserialize)]
pub struct WorkerStatusResponse {
    pub valid: bool,
    pub plan: Option<String>,
    pub cycle: Option<String>,
    pub email: Option<String>,
    pub status: Option<String>,
    pub valid_until: Option<String>,
}
