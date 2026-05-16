use crate::app::support::error::{AppError, AppResult};

use super::types::{InvoicesPageDto, WorkerInvoicesResponse};

const AKIRA_API_URL: &str = env!("AKIRA_BILLING_URL");

pub async fn list_invoices(token: String, cursor: Option<String>) -> AppResult<InvoicesPageDto> {
    let client = reqwest::Client::new();
    let mut query = vec![("token", token)];
    if let Some(c) = cursor {
        query.push(("starting_after", c));
    }

    let res = client
        .get(format!("{AKIRA_API_URL}/billing/invoices"))
        .query(&query)
        .send()
        .await
        .map_err(AppError::Http)?;

    if !res.status().is_success() {
        let msg = res.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("Invoices failed: {msg}")));
    }

    let body: WorkerInvoicesResponse = res.json().await.map_err(AppError::Http)?;
    Ok(InvoicesPageDto {
        invoices: body.invoices,
        has_more: body.has_more,
        next_cursor: body.next_cursor,
    })
}
