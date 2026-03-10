use std::path::PathBuf;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;
use tauri::Manager;

use crate::error::AppResult;

pub mod models;
pub mod organization_repository;
pub mod organization_repo_repository;
pub mod provider_repository;

fn database_path(app: &tauri::AppHandle) -> AppResult<PathBuf> {
    let app_dir = app.path().app_data_dir()?;
    std::fs::create_dir_all(&app_dir)?;
    Ok(app_dir.join("unified-dev.sqlite"))
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

    sqlx::migrate!().run(&pool).await?;

    Ok(pool)
}
