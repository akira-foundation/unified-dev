use std::path::Path;
use crate::error::{AppError, AppResult};
use crate::threads::create_thread::{create_initial_thread, ThreadConfig};

pub async fn add_thread(repo_id: String, pool: &sqlx::SqlitePool) -> AppResult<ThreadConfig> {
    let row = sqlx::query_as::<_, (String, String, String)>(
        "SELECT workspace_root, name, source_path FROM local_repositories WHERE id = ?",
    )
    .bind(&repo_id)
    .fetch_optional(pool)
    .await?;

    let (workspace_root, _name, source_path) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    let workspace_root = Path::new(&workspace_root).to_path_buf();
    let base_repo_path = workspace_root.join("repo");

    if !base_repo_path.exists() {
        return Err(AppError::Internal("Base repository clone not found".to_string()));
    }

    create_initial_thread(repo_id, &base_repo_path, &workspace_root, Path::new(&source_path), pool).await
}
