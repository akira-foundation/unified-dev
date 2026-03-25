use std::path::Path;

use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::threads::create_thread::create_initial_thread;
use crate::workspaces::git;
use crate::workspaces::local::{AddLocalRepositoryResponse, LocalRepository};

pub async fn add_remote_repository(
    url: String,
    pool: &sqlx::SqlitePool,
) -> AppResult<AddLocalRepositoryResponse> {
    let repo_name = git::repo_name_from_url(&url)
        .ok_or_else(|| AppError::Internal("Could not parse repository name from URL.".to_string()))?;

    let home_dir = dirs::home_dir()
        .ok_or_else(|| AppError::Internal("Could not find home directory".to_string()))?;
    let workspace_root = home_dir.join(".unifieddev").join("workspaces").join(&repo_name);

    if !workspace_root.exists() {
        std::fs::create_dir_all(&workspace_root).map_err(AppError::Io)?;
    }

    let base_repo_path = workspace_root.join("repo");
    if !base_repo_path.exists() {
        git::clone_from_url(&url, &base_repo_path)?;
    }

    let default_branch = git::get_default_branch(&base_repo_path)?;

    let existing: Option<(String,)> =
        sqlx::query_as("SELECT id FROM local_repositories WHERE source_path = ? LIMIT 1")
            .bind(&url)
            .fetch_optional(pool)
            .await?;

    if existing.is_some() {
        return Err(AppError::Internal(format!(
            "The repository '{}' has already been added.",
            repo_name
        )));
    }

    let repo_id = Uuid::new_v4().to_string().to_uppercase();
    let repository = LocalRepository {
        id: repo_id.clone(),
        name: repo_name,
        default_branch,
        source_path: url.clone(),
        workspace_root: workspace_root.to_string_lossy().to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    sqlx::query(
        "INSERT INTO local_repositories (id, name, default_branch, source_path, workspace_root, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&repository.id)
    .bind(&repository.name)
    .bind(&repository.default_branch)
    .bind(&repository.source_path)
    .bind(&repository.workspace_root)
    .bind(&repository.created_at)
    .execute(pool)
    .await?;

    let thread = create_initial_thread(
        repo_id,
        &base_repo_path,
        &workspace_root,
        Path::new(""),
        Some(url),
        pool,
    )
    .await?;

    Ok(AddLocalRepositoryResponse { repository, thread })
}
