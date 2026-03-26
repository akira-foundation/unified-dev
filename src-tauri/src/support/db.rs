use tauri::AppHandle;

use crate::support::error::AppResult;

pub async fn init_pool(app: &AppHandle) -> AppResult<sqlx::SqlitePool> {
    crate::db::init_pool(app).await
}
