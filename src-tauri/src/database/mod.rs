use std::path::PathBuf;

use sqlx::sqlite::{SqliteConnectOptions, SqlitePoolOptions};
use sqlx::SqlitePool;
use tauri::Manager;

use crate::app::support::error::AppResult;

pub mod models;
pub mod queries;

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

    sqlx::migrate!("./src/database/migrations").run(&pool).await?;

    Ok(pool)
}
