use akira_billing::types::Invoice;

use crate::app::billing::BillingClient;
use crate::app::support::error::{AppError, AppResult};

use super::types::{InvoiceDto, InvoicesPageDto};

pub async fn list_invoices(billing: &BillingClient, cursor: Option<String>) -> AppResult<InvoicesPageDto> {
    let page = billing
        .inner()
        .invoices(cursor.as_deref())
        .await
        .map_err(|e| AppError::Internal(format!("billing invoices: {e}")))?;

    Ok(InvoicesPageDto {
        invoices: page.invoices.into_iter().map(to_dto).collect(),
        has_more: page.has_more,
        next_cursor: page.next_cursor,
    })
}

fn to_dto(invoice: Invoice) -> InvoiceDto {
    InvoiceDto {
        id: invoice.id,
        number: invoice.number,
        amount: invoice.amount,
        currency: invoice.currency,
        date: invoice.date,
        period_start: invoice.period_start,
        period_end: invoice.period_end,
        pdf_url: invoice.pdf_url,
        hosted_url: invoice.hosted_url,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_sdk_invoice_to_dto() {
        let dto = to_dto(Invoice {
            id: "in_1".to_string(),
            number: Some("INV-1".to_string()),
            amount: 1500,
            currency: "eur".to_string(),
            date: "2026-01-01T00:00:00+00:00".to_string(),
            period_start: "2026-01-01T00:00:00+00:00".to_string(),
            period_end: "2026-02-01T00:00:00+00:00".to_string(),
            pdf_url: Some("https://pdf".to_string()),
            hosted_url: None,
        });

        assert_eq!(dto.id, "in_1");
        assert_eq!(dto.number.as_deref(), Some("INV-1"));
        assert_eq!(dto.amount, 1500);
        assert_eq!(dto.currency, "eur");
        assert_eq!(dto.hosted_url, None);
    }
}
