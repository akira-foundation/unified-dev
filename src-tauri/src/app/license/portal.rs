use crate::app::billing::BillingClient;
use crate::app::support::error::{AppError, AppResult};

const AKIRA_API_URL: &str = env!("AKIRA_BILLING_URL");

pub async fn portal(billing: &BillingClient) -> AppResult<String> {
    let return_url = if AKIRA_API_URL.is_empty() {
        "http://billing.test"
    } else {
        AKIRA_API_URL
    };

    let link = billing
        .inner()
        .billing_portal(return_url)
        .await
        .map_err(|e| AppError::Internal(format!("billing portal failed: {e}")))?;

    Ok(link.url)
}
