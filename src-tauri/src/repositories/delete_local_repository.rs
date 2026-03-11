use std::path::Path;
use sqlx::Row;
use crate::error::{AppError, AppResult};

pub async fn delete_local_repository(
    repo_id: String,
    pool: &sqlx::SqlitePool,
) -> AppResult<()> {
    let repo_record = sqlx::query("SELECT workspace_root FROM local_repositories WHERE id = ?")
        .bind(&repo_id)
        .fetch_optional(pool)
        .await?;

    if let Some(row) = repo_record {
        let workspace_root: String = row.try_get("workspace_root").map_err(|e| AppError::Database(e))?;
        let workspace_path = Path::new(&workspace_root);
        if workspace_path.exists() {
            std::fs::remove_dir_all(workspace_path).map_err(AppError::Io)?;
        }
    }

    sqlx::query("DELETE FROM threads WHERE repo_id = ?")
        .bind(&repo_id)
        .execute(pool)
        .await?;

    sqlx::query("DELETE FROM local_repositories WHERE id = ?")
        .bind(&repo_id)
        .execute(pool)
        .await?;

    Ok(())
}
