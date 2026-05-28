use std::collections::HashMap;

use akira_billing::desktop::PublicKeyStore;
use akira_billing::license::{decode_license, verify_license};
use akira_billing::types::{LicensePublicKey, LicenseSnapshotPayload, SignedLicense};
use akira_billing::Client;

use crate::app::support::error::{AppError, AppResult};

const AKIRA_LICENSE_PUBKEY: &str = env!("AKIRA_LICENSE_PUBKEY");

fn baked_public_keys() -> HashMap<String, String> {
    PublicKeyStore::parse(AKIRA_LICENSE_PUBKEY).snapshot()
}

pub async fn store_public_keys(pool: &sqlx::SqlitePool, keys: &[LicensePublicKey]) -> AppResult<()> {
    let now = chrono::Utc::now().to_rfc3339();
    for key in keys {
        sqlx::query(
            "INSERT INTO license_public_keys (key_id, algorithm, public_key_base64, fetched_at)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(key_id) DO UPDATE SET
                algorithm = excluded.algorithm,
                public_key_base64 = excluded.public_key_base64,
                fetched_at = excluded.fetched_at",
        )
        .bind(&key.key_id)
        .bind(&key.algorithm)
        .bind(&key.public_key_base64)
        .bind(&now)
        .execute(pool)
        .await?;
    }
    Ok(())
}

pub async fn cached_public_keys(pool: &sqlx::SqlitePool) -> AppResult<HashMap<String, String>> {
    let rows = sqlx::query_as::<_, (String, String)>(
        "SELECT key_id, public_key_base64 FROM license_public_keys",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows.into_iter().collect())
}

pub async fn resolve_public_keys(pool: &sqlx::SqlitePool) -> AppResult<HashMap<String, String>> {
    let cached = cached_public_keys(pool).await?;
    if !cached.is_empty() {
        return Ok(cached);
    }
    let baked = baked_public_keys();
    if !baked.is_empty() {
        return Ok(baked);
    }
    Err(AppError::Internal(
        "no license signing keys available (cache empty, AKIRA_LICENSE_PUBKEY unset)".into(),
    ))
}

pub async fn refresh_public_keys(
    pool: &sqlx::SqlitePool,
    client: &Client,
) -> AppResult<HashMap<String, String>> {
    match client.public_license_keys().await {
        Ok(response) if !response.keys.is_empty() => {
            store_public_keys(pool, &response.keys).await?;
            Ok(response
                .keys
                .into_iter()
                .map(|k| (k.key_id, k.public_key_base64))
                .collect())
        }
        _ => resolve_public_keys(pool).await,
    }
}

pub async fn verify_envelope(
    pool: &sqlx::SqlitePool,
    envelope: &SignedLicenseEnvelope,
) -> AppResult<LicenseSnapshotPayload> {
    let keys = resolve_public_keys(pool).await?;
    let signed = SignedLicense {
        key_id: envelope.key_id.clone(),
        algorithm: envelope.algorithm.clone(),
        payload: envelope.payload.clone(),
        signature: envelope.signature.clone(),
        valid_until: String::new(),
    };
    let pk = keys.get(&envelope.key_id).ok_or_else(|| {
        AppError::Internal(format!("unknown signing key_id: {}", envelope.key_id))
    })?;
    let valid = verify_license(&signed, pk)
        .map_err(|e| AppError::Internal(format!("license verify failed: {e}")))?;
    if !valid {
        return Err(AppError::Internal(
            "license signature verification failed".into(),
        ));
    }
    let decoded = decode_license(&signed)
        .map_err(|e| AppError::Internal(format!("license decode failed: {e}")))?;
    Ok(decoded.payload)
}

#[derive(Debug, Clone)]
pub struct SignedLicenseEnvelope {
    pub key_id: String,
    pub algorithm: String,
    pub payload: String,
    pub signature: String,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::setup_test_db;

    fn key(id: &str, pk: &str) -> LicensePublicKey {
        LicensePublicKey {
            key_id: id.to_string(),
            algorithm: "ed25519".to_string(),
            public_key_base64: pk.to_string(),
        }
    }

    #[tokio::test]
    async fn store_and_resolve_returns_cached_keys() {
        let pool = setup_test_db().await;
        store_public_keys(&pool, &[key("dev", "AAAA"), key("spectra", "BBBB")])
            .await
            .expect("store");

        let resolved = resolve_public_keys(&pool).await.expect("resolve");
        assert_eq!(resolved.get("dev").map(String::as_str), Some("AAAA"));
        assert_eq!(resolved.get("spectra").map(String::as_str), Some("BBBB"));
    }

    #[tokio::test]
    async fn upsert_rotates_key_without_duplicating() {
        let pool = setup_test_db().await;
        store_public_keys(&pool, &[key("dev", "OLD")]).await.expect("first");
        store_public_keys(&pool, &[key("dev", "NEW")]).await.expect("second");

        let cached = cached_public_keys(&pool).await.expect("cached");
        assert_eq!(cached.len(), 1);
        assert_eq!(cached.get("dev").map(String::as_str), Some("NEW"));
    }
}
