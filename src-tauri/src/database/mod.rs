use std::path::PathBuf;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;
use tauri::Manager;

use crate::app::support::error::AppResult;
use crate::app::support::security::{derive_db_key, DbKeyStore};

pub mod records;

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

pub async fn init_pool(app: &tauri::AppHandle) -> AppResult<SqlitePool> {
    let db_path = database_path(app)?;
    let connect_options = SqliteConnectOptions::new()
        .filename(db_path)
        .create_if_missing(true)
        .foreign_keys(true);

    let pool = SqlitePoolOptions::new()
        .max_connections(5)
        .connect_with(connect_options)
        .await?;

    sqlx::migrate!("./src/database/migrations").run(&pool).await?;

    Ok(pool)
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
}
