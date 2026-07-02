use std::path::{Path, PathBuf};

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};

use crate::app::support::error::AppResult;
use crate::app::support::security::{derive_db_key, DbKeyStore};

pub async fn migrate_legacy_if_needed(app: &tauri::AppHandle, customer_id: &str) -> AppResult<()> {
    let legacy_path = super::database_path(app)?;
    let target_path = super::customer_db_path(app, customer_id)?;
    let master_key = DbKeyStore::load_or_create_master_key(app)?;
    let key_hex = hex::encode(derive_db_key(&master_key, customer_id));

    migrate_legacy_db(&legacy_path, &target_path, customer_id, &key_hex).await
}

async fn migrate_legacy_db(
    legacy_path: &Path,
    target_path: &Path,
    customer_id: &str,
    key_hex: &str,
) -> AppResult<()> {
    if !legacy_path.exists() || target_path.exists() {
        return Ok(());
    }

    let legacy_pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect_with(
            SqliteConnectOptions::new()
                .filename(legacy_path)
                .create_if_missing(true),
        )
        .await?;

    let legacy_customer_id: Option<String> =
        sqlx::query_scalar("SELECT customer_id FROM license WHERE id = 'local'")
            .fetch_optional(&legacy_pool)
            .await
            .ok()
            .flatten();

    if legacy_customer_id.as_deref() != Some(customer_id) {
        legacy_pool.close().await;
        return Ok(());
    }

    let target_path_str = target_path.to_string_lossy().replace('\'', "''");
    sqlx::query(&format!(
        "ATTACH DATABASE '{target_path_str}' AS encrypted KEY \"x'{key_hex}'\""
    ))
    .execute(&legacy_pool)
    .await?;
    sqlx::query("SELECT sqlcipher_export('encrypted')")
        .execute(&legacy_pool)
        .await?;
    sqlx::query("DETACH DATABASE encrypted")
        .execute(&legacy_pool)
        .await?;
    legacy_pool.close().await;

    let migrated_path = PathBuf::from(format!("{}.migrated", legacy_path.display()));
    std::fs::rename(legacy_path, migrated_path)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn seed_legacy_db(path: &Path, customer_id: Option<&str>) {
        let pool = SqlitePoolOptions::new()
            .max_connections(1)
            .connect_with(SqliteConnectOptions::new().filename(path).create_if_missing(true))
            .await
            .unwrap();
        sqlx::migrate!("./src/database/migrations")
            .run(&pool)
            .await
            .unwrap();
        sqlx::query("INSERT INTO license (id, customer_id) VALUES ('local', ?)")
            .bind(customer_id)
            .execute(&pool)
            .await
            .unwrap();
        sqlx::query("INSERT INTO providers (id, name, kind, auth_type, auth_payload, created_at) VALUES ('p1', 'gh', 'github', 'pat', '{}', '2026-01-01')")
            .execute(&pool)
            .await
            .unwrap();
        pool.close().await;
    }

    async fn open_encrypted(path: &Path, key_hex: &str) -> sqlx::SqlitePool {
        let key_hex = key_hex.to_string();
        SqlitePoolOptions::new()
            .max_connections(1)
            .after_connect(move |conn, _meta| {
                let key_hex = key_hex.clone();
                Box::pin(async move {
                    sqlx::query(&format!("PRAGMA key = \"x'{key_hex}'\""))
                        .execute(&mut *conn)
                        .await?;
                    Ok(())
                })
            })
            .connect_with(SqliteConnectOptions::new().filename(path))
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn migrates_matching_customer_and_renames_legacy() {
        let dir = tempfile::tempdir().unwrap();
        let legacy_path = dir.path().join("unified-dev.sqlite");
        let target_path = dir.path().join("unified.db");
        seed_legacy_db(&legacy_path, Some("cust-1")).await;

        migrate_legacy_db(&legacy_path, &target_path, "cust-1", &"aa".repeat(32))
            .await
            .unwrap();

        assert!(!legacy_path.exists());
        assert!(dir.path().join("unified-dev.sqlite.migrated").exists());
        assert!(target_path.exists());

        let migrated = open_encrypted(&target_path, &"aa".repeat(32)).await;
        let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM providers")
            .fetch_one(&migrated)
            .await
            .unwrap();
        assert_eq!(count, 1);
    }

    #[tokio::test]
    async fn skips_when_legacy_customer_id_differs() {
        let dir = tempfile::tempdir().unwrap();
        let legacy_path = dir.path().join("unified-dev.sqlite");
        let target_path = dir.path().join("unified.db");
        seed_legacy_db(&legacy_path, Some("cust-1")).await;

        migrate_legacy_db(&legacy_path, &target_path, "cust-2", &"bb".repeat(32))
            .await
            .unwrap();

        assert!(legacy_path.exists(), "legacy db must be left untouched");
        assert!(!target_path.exists());
    }

    #[tokio::test]
    async fn skips_when_legacy_customer_id_is_null() {
        let dir = tempfile::tempdir().unwrap();
        let legacy_path = dir.path().join("unified-dev.sqlite");
        let target_path = dir.path().join("unified.db");
        seed_legacy_db(&legacy_path, None).await;

        migrate_legacy_db(&legacy_path, &target_path, "cust-1", &"cc".repeat(32))
            .await
            .unwrap();

        assert!(legacy_path.exists());
        assert!(!target_path.exists());
    }

    #[tokio::test]
    async fn skips_when_target_already_exists() {
        let dir = tempfile::tempdir().unwrap();
        let legacy_path = dir.path().join("unified-dev.sqlite");
        let target_path = dir.path().join("unified.db");
        seed_legacy_db(&legacy_path, Some("cust-1")).await;
        std::fs::write(&target_path, b"already here").unwrap();

        migrate_legacy_db(&legacy_path, &target_path, "cust-1", &"dd".repeat(32))
            .await
            .unwrap();

        assert!(legacy_path.exists(), "must not touch legacy once target exists");
    }

    #[tokio::test]
    async fn skips_when_no_legacy_db() {
        let dir = tempfile::tempdir().unwrap();
        let legacy_path = dir.path().join("unified-dev.sqlite");
        let target_path = dir.path().join("unified.db");

        migrate_legacy_db(&legacy_path, &target_path, "cust-1", &"ee".repeat(32))
            .await
            .unwrap();

        assert!(!target_path.exists());
    }
}
