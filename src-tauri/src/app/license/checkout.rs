use crate::app::support::error::{AppError, AppResult};
use super::types::CheckoutDto;

const AKIRA_API_URL: &str = env!("AKIRA_BILLING_URL");

pub async fn checkout(plan: String, cycle: String) -> AppResult<CheckoutDto> {
    let client = reqwest::Client::new();
    let res = client
        .post(format!("{AKIRA_API_URL}/billing/checkout"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({ "plan": plan, "cycle": cycle }))
        .send()
        .await
        .map_err(AppError::Http)?;

    if !res.status().is_success() {
        let msg = res.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("Checkout failed: {msg}")));
    }

    let body: serde_json::Value = res.json().await.map_err(AppError::Http)?;
    let url = body["url"]
        .as_str()
        .ok_or_else(|| AppError::Internal("No URL in checkout response".into()))?
        .to_string();
    let session_id = body["session_id"]
        .as_str()
        .ok_or_else(|| AppError::Internal("No session_id in checkout response".into()))?
        .to_string();

    Ok(CheckoutDto { url, session_id })
}
