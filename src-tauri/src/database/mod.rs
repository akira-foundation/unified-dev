use std::path::PathBuf;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;
use tauri::Manager;

use crate::app::support::error::AppResult;

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
