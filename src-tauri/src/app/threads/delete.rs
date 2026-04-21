use std::path::Path;
use crate::app::support::error::{AppError, AppResult};

pub async fn delete(thread_id: String, pool: &sqlx::SqlitePool) -> AppResult<()> {
    let row = sqlx::query_as::<_, (String,)>(
        "SELECT workspace_path FROM threads WHERE id = ?",
    )
    .bind(&thread_id)
    .fetch_optional(pool)
    .await?;

    let (workspace_path,) = row.ok_or_else(|| {
        AppError::Internal(format!("Thread '{}' not found", thread_id))
    })?;

    let path = Path::new(&workspace_path);
    if path.exists() {
        if path.is_dir() {
            let _ = std::fs::remove_dir_all(path);
        } else {
            let _ = std::fs::remove_file(path);
        }
    }

    sqlx::query("DELETE FROM threads WHERE id = ?")
        .bind(&thread_id)
        .execute(pool)
        .await?;

    Ok(())
}
