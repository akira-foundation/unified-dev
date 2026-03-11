use std::path::Path;
use crate::error::{AppError, AppResult};

pub async fn delete_thread(thread_id: String, pool: &sqlx::SqlitePool) -> AppResult<()> {
    // 1. Get workspace path from DB
    let row = sqlx::query_as::<_, (String,)>(
        "SELECT workspace_path FROM threads WHERE id = ?",
    )
    .bind(&thread_id)
    .fetch_optional(pool)
    .await?;

    let (workspace_path,) = row.ok_or_else(|| {
        AppError::Internal(format!("Thread '{}' not found", thread_id))
    })?;

    // 2. Delete workspace folder
    let path = Path::new(&workspace_path);
    if path.exists() {
        if path.is_dir() {
            std::fs::remove_dir_all(path).map_err(AppError::Io)?;
        } else {
            std::fs::remove_file(path).map_err(AppError::Io)?;
        }
    }

    // 3. Delete from DB
    sqlx::query("DELETE FROM threads WHERE id = ?")
        .bind(&thread_id)
        .execute(pool)
        .await?;

    Ok(())
}
