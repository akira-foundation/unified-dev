use akira_billing::types::DowngradePayload;
use serde::{Deserialize, Serialize};

use crate::app::billing::{BillingClient, PRODUCT_SLUG};
use crate::app::support::error::{AppError, AppResult};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DowngradeDto {
    pub cancel_at_period_end: bool,
    pub cancel_at: Option<String>,
    pub plan: Option<String>,
    pub valid_until: Option<String>,
    pub signature: Option<String>,
    pub target_plan: Option<String>,
}

pub async fn downgrade(billing: &BillingClient, target_plan: String) -> AppResult<DowngradeDto> {
    let target = match target_plan.trim() {
        "" | "free" => None,
        plan => Some(plan),
    };

    let response = billing
        .inner()
        .downgrade_subscription(DowngradePayload {
            product: PRODUCT_SLUG,
            target_plan: target,
        })
        .await
        .map_err(|e| AppError::Internal(format!("downgrade failed: {e}")))?;

    Ok(to_dto(response))
}

pub async fn resume(billing: &BillingClient) -> AppResult<DowngradeDto> {
    let response = billing
        .inner()
        .resume_subscription(PRODUCT_SLUG)
        .await
        .map_err(|e| AppError::Internal(format!("resume failed: {e}")))?;

    Ok(to_dto(response))
}

fn to_dto(response: akira_billing::types::DowngradeResponse) -> DowngradeDto {
    DowngradeDto {
        cancel_at_period_end: response.cancel_at_period_end,
        cancel_at: response.cancel_at,
        plan: response.plan,
        valid_until: response.valid_until,
        signature: response.signature,
        target_plan: response.target_plan,
    }
}

pub async fn apply_downgrade(pool: &sqlx::SqlitePool, dto: &DowngradeDto) -> AppResult<()> {
    sqlx::query(
        "UPDATE license SET cancel_at_period_end = ?, cancel_at = ?, target_plan = ? WHERE id = 'local'",
    )
    .bind(dto.cancel_at_period_end)
    .bind(dto.cancel_at.as_deref())
    .bind(dto.target_plan.as_deref())
    .execute(pool)
    .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_license, setup_test_db};

    #[tokio::test]
    async fn apply_downgrade_persists_cancel_fields() {
        let pool = setup_test_db().await;
        seed_license(&pool, "pro", false).await;

        let dto = DowngradeDto {
            cancel_at_period_end: true,
            cancel_at: Some("2099-01-01T00:00:00+00:00".to_string()),
            plan: Some("pro".to_string()),
            valid_until: Some("2099-01-01T00:00:00+00:00".to_string()),
            signature: None,
            target_plan: Some("free".to_string()),
        };

        apply_downgrade(&pool, &dto).await.expect("apply_downgrade");

        let row = sqlx::query_as::<_, (i64, Option<String>, Option<String>)>(
            "SELECT cancel_at_period_end, cancel_at, target_plan FROM license WHERE id = 'local'",
        )
        .fetch_one(&pool)
        .await
        .expect("row");

        assert_eq!(row.0, 1);
        assert_eq!(row.1.as_deref(), Some("2099-01-01T00:00:00+00:00"));
        assert_eq!(row.2.as_deref(), Some("free"));
    }
}
