use std::path::Path;
use uuid::Uuid;
use crate::error::AppResult;
use crate::repositories::git_utils;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct ThreadConfig {
    pub id: String,
    pub repo_id: String,
    pub title: String,
    pub workspace_path: String,
    pub branch: String,
    pub status: String,
    pub created_at: String,
}

pub async fn create_initial_thread(
    repo_id: String,
    base_repo_path: &Path,
    workspace_root: &Path,
    pool: &sqlx::SqlitePool,
) -> AppResult<ThreadConfig> {
    let thread_id = Uuid::new_v4().to_string().to_uppercase();
    let thread_branch = format!("thread/{}", thread_id);
    let title = "New thread".to_string();
    let workspace_path = workspace_root.join(&thread_id);

    git_utils::clone_repository(base_repo_path, &workspace_path)?;

    git_utils::create_branch(&workspace_path, &thread_branch)?;

    let thread = ThreadConfig {
        id: thread_id.clone(),
        repo_id,
        title,
        workspace_path: workspace_path.to_string_lossy().to_string(),
        branch: thread_branch,
        status: "active".to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    sqlx::query(
        r#"
        INSERT INTO threads (id, repo_id, title, workspace_path, branch, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        "#,
    )
    .bind(&thread.id)
    .bind(&thread.repo_id)
    .bind(&thread.title)
    .bind(&thread.workspace_path)
    .bind(&thread.branch)
    .bind(&thread.status)
    .bind(&thread.created_at)
    .execute(pool)
    .await?;

    Ok(thread)
}
