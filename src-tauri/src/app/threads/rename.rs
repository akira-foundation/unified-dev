use std::path::Path;

use crate::app::support::error::{AppError, AppResult};
use crate::app::threads::list_repos::ThreadRow;

fn validate_name(name: &str) -> AppResult<()> {
    if name.is_empty() {
        return Err(AppError::Internal("Thread name cannot be empty".to_string()));
    }
    if name.contains("..") || name.contains('/') || name.contains('\\') {
        return Err(AppError::Internal("Thread name must not contain path separators or '..'".to_string()));
    }
    if !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_') {
        return Err(AppError::Internal(
            "Thread name must only contain letters, digits, hyphens, and underscores".to_string(),
        ));
    }
    Ok(())
}

pub async fn rename(thread_id: &str, new_name: &str, pool: &sqlx::SqlitePool) -> AppResult<ThreadRow> {
    validate_name(new_name)?;

    let row = sqlx::query_as::<_, (String, String, String, String, String, Option<String>, Option<i64>)>(
        "SELECT title, branch, workspace_path, status, created_at, pr_url, pr_is_draft FROM threads WHERE id = ?",
    )
    .bind(thread_id)
    .fetch_optional(pool)
    .await?;

    let (_, branch, workspace_path, status, created_at, pr_url, pr_is_draft) =
        row.ok_or_else(|| AppError::Internal(format!("Thread '{}' not found", thread_id)))?;

    let old_path = Path::new(&workspace_path);
    let parent = old_path.parent().ok_or_else(|| {
        AppError::Internal(format!("Cannot determine parent directory of '{}'", workspace_path))
    })?;
    let new_path = parent.join(new_name);

    if new_path.exists() {
        return Err(AppError::Internal(format!(
            "A workspace named '{}' already exists",
            new_name
        )));
    }

    std::fs::rename(old_path, &new_path).map_err(|e| {
        AppError::Internal(format!(
            "Failed to rename workspace directory: {}",
            e
        ))
    })?;

    let new_workspace_path = new_path.to_string_lossy().to_string();

    sqlx::query("UPDATE threads SET title = ?, workspace_path = ? WHERE id = ?")
        .bind(new_name)
        .bind(&new_workspace_path)
        .bind(thread_id)
        .execute(pool)
        .await?;

    Ok(ThreadRow {
        id: thread_id.to_string(),
        title: new_name.to_string(),
        branch,
        workspace_path: new_workspace_path,
        status,
        created_at,
        pr_url,
        pr_is_draft: pr_is_draft.unwrap_or(0) != 0,
    })
}
