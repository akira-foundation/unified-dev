use akira_billing::desktop::{activate_or_refresh, ActivateOrRefreshOptions};
use akira_billing::Error as BillingError;

use crate::app::billing::{BillingClient, PRODUCT_SLUG};
use crate::app::support::error::AppResult;

use super::persist;
use super::signed_license::{refresh_public_keys, Keyring};
use super::types::LicenseDto;

const GRACE_PERIOD_DAYS: i64 = 5;

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

pub async fn verify(
    pool: &sqlx::SqlitePool,
    billing: &BillingClient,
    fingerprint: &str,
) -> AppResult<Option<LicenseDto>> {
    let cached = get(pool).await?;
    let Some(license) = cached else {
        return Ok(None);
    };

    if !billing.has_customer_token() {
        return Ok(Some(license));
    }

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
        Ok(verified) => Ok(Some(persist::store_verified(pool, &verified).await?)),
        Err(BillingError::Api { status: 401..=403, .. }) => {
            Ok(Some(downgrade_to_free(pool).await?))
        }
        Err(_) => offline_fallback(pool, license).await,
    }
}

async fn offline_fallback(pool: &sqlx::SqlitePool, license: LicenseDto) -> AppResult<Option<LicenseDto>> {
    let Some(envelope) = persist::load_envelope(pool).await? else {
        return Ok(Some(license));
    };

    let keyring = Keyring::from_cache(pool).await?;
    if keyring.verify(&envelope).is_err() {
        return Ok(Some(downgrade_to_free(pool).await?));
    }

    let last_verified = chrono::DateTime::parse_from_rfc3339(&license.last_verified_at)
        .map(|dt| dt.with_timezone(&chrono::Utc))
        .unwrap_or(chrono::DateTime::<chrono::Utc>::MIN_UTC);
    let days_offline = chrono::Utc::now().signed_duration_since(last_verified).num_days();

    if days_offline >= GRACE_PERIOD_DAYS {
        return Ok(Some(downgrade_to_free(pool).await?));
    }

    Ok(Some(LicenseDto { grace_period: true, ..license }))
}

async fn downgrade_to_free(pool: &sqlx::SqlitePool) -> AppResult<LicenseDto> {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE license SET plan = 'free', status = 'active', last_verified_at = ?,
            license_key_id = NULL, license_algorithm = NULL, license_payload = NULL,
            license_signature = NULL, features_json = NULL
         WHERE id = 'local'",
    )
    .bind(&now)
    .execute(pool)
    .await?;

    Ok(get(pool).await?.unwrap_or_else(|| LicenseDto {
        token: String::new(),
        plan: "free".to_string(),
        cycle: String::new(),
        email: String::new(),
        status: "active".to_string(),
        valid_until: String::new(),
        activated_at: String::new(),
        last_verified_at: now,
        signature: String::new(),
        grace_period: false,
        cancel_at_period_end: None,
        cancel_at: None,
        target_plan: None,
    }))
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
    async fn downgrade_resets_plan_and_clears_envelope() {
        let pool = setup_test_db().await;
        seed_license(&pool, "pro", true).await;

        let dto = downgrade_to_free(&pool).await.expect("downgrade");
        assert_eq!(dto.plan, "free");
        assert_eq!(dto.status, "active");
        assert!(persist::load_envelope(&pool).await.expect("load").is_none());
    }
}
