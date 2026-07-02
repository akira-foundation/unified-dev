use std::path::PathBuf;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;
use tauri::Manager;

use crate::app::support::error::AppResult;
use crate::app::support::security::{derive_db_key, DbKeyStore};

pub mod legacy_migration;
pub mod records;

pub use legacy_migration::migrate_legacy_if_needed;

pub fn database_path(app: &tauri::AppHandle) -> AppResult<PathBuf> {
    let app_dir = app.path().app_data_dir()?;
    std::fs::create_dir_all(&app_dir)?;
    let filename = if cfg!(debug_assertions) {
        let tag = std::env::var("UNIFIED_DEV_DB_TAG").unwrap_or_default();
        if tag.is_empty() {
            "unified-dev-local.sqlite".to_string()
        } else {
            format!("unified-dev-local-{tag}.sqlite")
        }
    } else {
        "unified-dev.sqlite".to_string()
    };
    Ok(app_dir.join(filename))
}

pub fn customer_db_path(app: &tauri::AppHandle, customer_id: &str) -> AppResult<PathBuf> {
    let app_dir = app.path().app_data_dir()?;
    let customer_dir = app_dir.join("Unified").join(customer_id);
    std::fs::create_dir_all(&customer_dir)?;
    let filename = if cfg!(debug_assertions) {
        let tag = std::env::var("UNIFIED_DEV_DB_TAG").unwrap_or_default();
        if tag.is_empty() {
            "unified.db".to_string()
        } else {
            format!("unified-{tag}.db")
        }
    } else {
        "unified.db".to_string()
    };
    Ok(customer_dir.join(filename))
}

pub async fn open_customer_pool(app: &tauri::AppHandle, customer_id: &str) -> AppResult<SqlitePool> {
    let db_path = customer_db_path(app, customer_id)?;
    let master_key = DbKeyStore::load_or_create_master_key(app)?;
    let key_hex = hex::encode(derive_db_key(&master_key, customer_id));

    let connect_options = SqliteConnectOptions::new()
        .filename(db_path)
        .create_if_missing(true);

    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .after_connect(move |conn, _meta| {
            let key_hex = key_hex.clone();
            Box::pin(async move {
                sqlx::query(&format!("PRAGMA key = \"x'{key_hex}'\""))
                    .execute(&mut *conn)
                    .await?;
                sqlx::query("PRAGMA journal_mode = WAL")
                    .execute(&mut *conn)
                    .await?;
                sqlx::query("PRAGMA foreign_keys = ON")
                    .execute(&mut *conn)
                    .await?;
                Ok(())
            })
        })
        .connect_with(connect_options)
        .await?;

    sqlx::migrate!("./src/database/migrations").run(&pool).await?;

    Ok(pool)
}

#[cfg(test)]
mod tests {
    use crate::test_utils::setup_test_db;

    #[tokio::test]
    async fn migrations_run_on_empty_db() {
        let pool = setup_test_db().await;
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='providers'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(count, 1, "providers table must exist after migrations");
    }

    #[tokio::test]
    async fn migrations_include_oss_tables() {
        let pool = setup_test_db().await;
        for table in [
            "github_contribution_profiles",
            "github_contributed_repositories",
            "github_pull_requests_oss",
            "github_issues_oss",
            "github_reviews_oss",
            "github_contribution_snapshots",
        ] {
            let count: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=?",
            )
            .bind(table)
            .fetch_one(&pool)
            .await
            .unwrap();
            assert_eq!(count, 1, "table {table} must exist after migrations");
        }
    }

    #[tokio::test]
    async fn license_table_only_tracks_session_identity_after_migrations() {
        let pool = setup_test_db().await;
        let columns: Vec<String> =
            sqlx::query_scalar("SELECT name FROM pragma_table_info('license') ORDER BY name")
                .fetch_all(&pool)
                .await
                .unwrap();
        assert_eq!(
            columns,
            vec!["customer_email", "customer_id", "customer_token_cipher", "id"]
        );

        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='license_public_keys'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(count, 0, "license_public_keys must be dropped");
    }

    #[tokio::test]
    async fn upgrade_preserves_customer_session_across_column_drop() {
        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .max_connections(1)
            .connect("sqlite::memory:")
            .await
            .unwrap();

        sqlx::query(
            "CREATE TABLE license (
                id TEXT NOT NULL DEFAULT 'local' PRIMARY KEY,
                token TEXT NOT NULL,
                plan TEXT NOT NULL,
                customer_id TEXT,
                customer_email TEXT,
                customer_token_cipher TEXT
            )",
        )
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO license (id, token, plan, customer_id, customer_email, customer_token_cipher)
             VALUES ('local', '', 'pro', 'cust-1', 'a@b.c', 'encrypted-blob')",
        )
        .execute(&pool)
        .await
        .unwrap();

        let drop_columns_sql = std::fs::read_to_string(
            "src/database/migrations/0051_drop_paywall_columns.sql",
        )
        .unwrap();
        for statement in drop_columns_sql.split(';').map(str::trim).filter(|s| !s.is_empty()) {
            if statement.contains("DROP COLUMN token") || statement.contains("DROP COLUMN plan") {
                sqlx::query(statement).execute(&pool).await.unwrap();
            }
        }

        let (customer_id, cipher): (Option<String>, Option<String>) = sqlx::query_as(
            "SELECT customer_id, customer_token_cipher FROM license WHERE id = 'local'",
        )
        .fetch_one(&pool)
        .await
        .unwrap();
        assert_eq!(customer_id.as_deref(), Some("cust-1"));
        assert_eq!(cipher.as_deref(), Some("encrypted-blob"));
    }
}
