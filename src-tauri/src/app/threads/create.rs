use std::path::Path;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::app::support::error::{AppError, AppResult};
use crate::app::repos::git;
use super::naming;

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

pub async fn create(repo_id: String, pool: &sqlx::SqlitePool) -> AppResult<ThreadConfig> {
    let row = sqlx::query_as::<_, (String, String, String, Option<String>)>(
        "SELECT workspace_root, name, source_path, remote_url FROM local_repositories WHERE id = ?",
    )
    .bind(&repo_id)
    .fetch_optional(pool)
    .await?;

    let (workspace_root, _name, source_path, remote_url) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    let workspace_root = Path::new(&workspace_root).to_path_buf();
    let base_repo_path = workspace_root.join("repo");

    if !base_repo_path.exists() {
        return Err(AppError::Internal("Base repository clone not found".to_string()));
    }

    create_with_paths(repo_id, &base_repo_path, &workspace_root, Path::new(&source_path), remote_url, pool).await
}

pub async fn create_with_title(
    repo_id: String,
    title: String,
    pool: &sqlx::SqlitePool,
) -> AppResult<ThreadConfig> {
    let row = sqlx::query_as::<_, (String, String, Option<String>)>(
        "SELECT workspace_root, source_path, remote_url FROM local_repositories WHERE id = ?",
    )
    .bind(&repo_id)
    .fetch_optional(pool)
    .await?;

    let (workspace_root, source_path, remote_url) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    let workspace_root = Path::new(&workspace_root).to_path_buf();
    let base_repo_path = workspace_root.join("repo");

    if !base_repo_path.exists() {
        return Err(AppError::Internal("Base repository clone not found".to_string()));
    }

    create_with_options(
        repo_id,
        &base_repo_path,
        &workspace_root,
        Path::new(&source_path),
        remote_url,
        Some(title),
        None,
        None,
        None,
        pool,
    )
    .await
}

pub async fn create_from_branch(
    repo_id: String,
    title: String,
    source_commit: String,
    pool: &sqlx::SqlitePool,
) -> AppResult<ThreadConfig> {
    let row = sqlx::query_as::<_, (String, String, Option<String>)>(
        "SELECT workspace_root, source_path, remote_url FROM local_repositories WHERE id = ?",
    )
    .bind(&repo_id)
    .fetch_optional(pool)
    .await?;

    let (workspace_root, source_path, remote_url) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    let workspace_root = Path::new(&workspace_root).to_path_buf();
    let base_repo_path = workspace_root.join("repo");

    if !base_repo_path.exists() {
        return Err(AppError::Internal("Base repository clone not found".to_string()));
    }

    create_with_options(
        repo_id,
        &base_repo_path,
        &workspace_root,
        Path::new(&source_path),
        remote_url,
        Some(title),
        None,
        None,
        Some(source_commit),
        pool,
    )
    .await
}

pub async fn create_from_pull_request(
    repo_id: String,
    title: String,
    head_sha: String,
    pool: &sqlx::SqlitePool,
) -> AppResult<ThreadConfig> {
    let row = sqlx::query_as::<_, (String, String, Option<String>)>(
        "SELECT workspace_root, source_path, remote_url FROM local_repositories WHERE id = ?",
    )
    .bind(&repo_id)
    .fetch_optional(pool)
    .await?;

    let (workspace_root, source_path, remote_url) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    let workspace_root = Path::new(&workspace_root).to_path_buf();
    let base_repo_path = workspace_root.join("repo");

    if !base_repo_path.exists() {
        return Err(AppError::Internal("Base repository clone not found".to_string()));
    }

    create_with_options(
        repo_id,
        &base_repo_path,
        &workspace_root,
        Path::new(&source_path),
        remote_url,
        Some(title),
        None,
        None,
        Some(head_sha),
        pool,
    )
    .await
}

pub async fn create_with_paths(
    repo_id: String,
    base_repo_path: &Path,
    workspace_root: &Path,
    source_path: &Path,
    remote_url_override: Option<String>,
    pool: &sqlx::SqlitePool,
) -> AppResult<ThreadConfig> {
    create_with_options(
        repo_id,
        base_repo_path,
        workspace_root,
        source_path,
        remote_url_override,
        None,
        None,
        None,
        None,
        pool,
    )
    .await
}

async fn create_with_options(
    repo_id: String,
    base_repo_path: &Path,
    workspace_root: &Path,
    source_path: &Path,
    remote_url_override: Option<String>,
    title_override: Option<String>,
    source_branch: Option<String>,
    source_ref: Option<String>,
    source_commit: Option<String>,
    pool: &sqlx::SqlitePool,
) -> AppResult<ThreadConfig> {
    let plan = crate::app::license::get_plan(pool).await?;
    if plan == "free" {
        let count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM threads WHERE status != 'closed'",
        )
        .fetch_one(pool)
        .await?;
        if count >= 3 {
            return Err(AppError::FreeTierLimit("thread_limit_reached".to_string()));
        }
    }

    let thread_uuid = Uuid::new_v4();
    let thread_id = thread_uuid.to_string().to_uppercase();
    let title = title_override
        .map(|value| naming::sanitize_thread_title(&value))
        .unwrap_or_else(|| naming::generate_thread_name(thread_uuid.as_u64_pair().0));
    let thread_branch = naming::unique_thread_branch(&repo_id, &title, pool).await?;
    let workspace_path = workspace_root.join(&thread_id);

    git::clone_repository(base_repo_path, &workspace_path)?;

    let github_url = remote_url_override
        .or_else(|| git::get_remote_url(source_path, "origin"));
    if let Some(url) = github_url {
        if git::is_github_url(&url) {
            let _ = git::set_remote_url(&workspace_path, "origin", &url);
        }
    }

    if let Some(git_ref) = source_ref {
        git::fetch_ref(&workspace_path, "origin", &git_ref)?;
        git::checkout_fetch_head(&workspace_path)?;
    }

    if let Some(commit) = source_commit {
        git::fetch_commit(&workspace_path, "origin", &commit)?;
        git::checkout_fetch_head(&workspace_path)?;
    }

    if let Some(branch) = source_branch {
        git::fetch_branch(&workspace_path, "origin", &branch)?;
        git::checkout_remote_branch(&workspace_path, "origin", &branch)?;
    }

    git::create_branch(&workspace_path, &thread_branch)?;

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
        "INSERT INTO threads (id, repo_id, title, workspace_path, branch, status, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)",
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
