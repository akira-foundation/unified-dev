use akira_billing::desktop::{activate_or_refresh, ActivateOrRefreshOptions};
use akira_billing::lifecycle::LicenseState;
use akira_billing::Error as BillingError;

use crate::app::billing::{BillingClient, PRODUCT_SLUG};
use crate::app::support::error::AppResult;

use super::lifecycle;
use super::persist;
use super::signed_license::refresh_public_keys;
use super::types::LicenseDto;

pub async fn get_plan(pool: &sqlx::SqlitePool) -> AppResult<String> {
    let plan = sqlx::query_scalar::<_, String>(
        "SELECT plan FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?
    .filter(|p| !p.is_empty())
    .unwrap_or_else(|| "free".to_string());
    Ok(plan)
}

pub async fn load_customer_token(
    pool: &sqlx::SqlitePool,
    cipher: &crate::app::support::security::TokenCipher,
) -> AppResult<Option<String>> {
    let cipher_blob = sqlx::query_scalar::<_, Option<String>>(
        "SELECT customer_token_cipher FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?
    .flatten();

    let Some(blob) = cipher_blob else {
        return Ok(None);
    };
    if blob.is_empty() {
        return Ok(None);
    }

    Ok(Some(cipher.decrypt(&blob)?))
}

pub async fn get(pool: &sqlx::SqlitePool) -> AppResult<Option<LicenseDto>> {
    let row = sqlx::query_as::<_, LicenseDto>(
        "SELECT token, plan, cycle, email, status, valid_until, activated_at, last_verified_at, signature, 0 as grace_period,
                CASE WHEN cancel_at_period_end = 1 THEN 1 ELSE 0 END as cancel_at_period_end,
                cancel_at, target_plan
         FROM license WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?;

    Ok(row)
}

pub async fn get_with_lifecycle(pool: &sqlx::SqlitePool) -> AppResult<Option<LicenseDto>> {
    let Some(mut dto) = get(pool).await? else {
        return Ok(None);
    };
    let state = lifecycle::current_state(pool).await?;
    dto.status = lifecycle::state_label(state).to_string();
    dto.grace_period = matches!(state, LicenseState::Grace);
    Ok(Some(dto))
}

pub async fn verify(
    pool: &sqlx::SqlitePool,
    billing: &BillingClient,
    fingerprint: &str,
) -> AppResult<Option<LicenseDto>> {
    let cached = get(pool).await?;
    let Some(_) = cached else {
        return Ok(None);
    };

    if billing.has_customer_token() {
        let options = ActivateOrRefreshOptions {
            product: PRODUCT_SLUG,
            fingerprint,
            device_type: "desktop",
            platform: Some(std::env::consts::OS),
            device_name: None,
            app_version: Some(env!("CARGO_PKG_VERSION")),
        };
        let keys = refresh_public_keys(pool, billing.inner()).await?;
        match activate_or_refresh(billing.inner(), &options, &keys).await {
            Ok(verified) => {
                persist::store_verified(pool, &verified).await?;
            }
            Err(BillingError::Api { status: 401..=403, .. }) => {
                mark_revoked(pool).await?;
            }
            Err(_) => {}
        }
    }

    get_with_lifecycle(pool).await
}

pub async fn mark_revoked(pool: &sqlx::SqlitePool) -> AppResult<()> {
    sqlx::query("UPDATE license SET status = 'revoked' WHERE id = 'local'")
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn clear(pool: &sqlx::SqlitePool) -> AppResult<()> {
    sqlx::query("DELETE FROM license WHERE id = 'local'")
        .execute(pool)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_license, setup_test_db};

    #[tokio::test]
    async fn mark_revoked_keeps_envelope_for_audit() {
        let pool = setup_test_db().await;
        seed_license(&pool, "pro", true).await;

        mark_revoked(&pool).await.expect("mark_revoked");

        assert!(persist::load_envelope(&pool).await.expect("load").is_some());
        let dto = get(&pool).await.expect("get").expect("dto");
        assert_eq!(dto.status, "revoked");
    }

    #[tokio::test]
    async fn get_with_lifecycle_returns_none_status_without_envelope() {
        let pool = setup_test_db().await;
        seed_license(&pool, "free", false).await;
        let dto = get_with_lifecycle(&pool).await.expect("get").expect("dto");
        assert_eq!(dto.status, "none");
        assert!(!dto.grace_period);
    }
}
