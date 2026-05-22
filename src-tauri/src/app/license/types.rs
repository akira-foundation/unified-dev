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
    pub device_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InvoiceDto {
    pub id: String,
    pub number: Option<String>,
    pub amount: i64,
    pub currency: String,
    pub date: String,
    pub period_start: String,
    pub period_end: String,
    pub pdf_url: Option<String>,
    pub hosted_url: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InvoicesPageDto {
    pub invoices: Vec<InvoiceDto>,
    pub has_more: bool,
    pub next_cursor: Option<String>,
}
