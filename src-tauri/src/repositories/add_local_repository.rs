use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use crate::error::{AppError, AppResult};
use crate::repositories::git_utils;
use crate::threads::create_thread::{create_initial_thread, ThreadConfig};

#[derive(Debug, Serialize, Deserialize)]
pub struct LocalRepository {
    pub id: String,
    pub name: String,
    pub default_branch: String,
    pub source_path: String,
    pub workspace_root: String,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AddLocalRepositoryResponse {
    pub repository: LocalRepository,
    pub thread: ThreadConfig,
}

pub async fn add_local_repository(
    local_path: String,
    pool: &sqlx::SqlitePool,
) -> AppResult<AddLocalRepositoryResponse> {
    let source_path = Path::new(&local_path);

    if !git_utils::is_git_repository(source_path) {
        return Err(AppError::Internal("This folder is not a git repository.".to_string()));
    }

    let repo_name = git_utils::get_repository_name(source_path)?;
    let default_branch = git_utils::get_default_branch(source_path)?;

    let home_dir = dirs::home_dir().ok_or_else(|| AppError::Internal("Could not find home directory".to_string()))?;
    let workspace_root = home_dir.join(".unifieddev").join("workspaces").join(&repo_name);

    if !workspace_root.exists() {
        std::fs::create_dir_all(&workspace_root).map_err(AppError::Io)?;
    }

    let base_repo_path = workspace_root.join("repo");
    if !base_repo_path.exists() {
        git_utils::clone_repository(source_path, &base_repo_path)?;
    }

    let repo_id = Uuid::new_v4().to_string().to_uppercase();
    
    let repository = LocalRepository {
        id: repo_id.clone(),
        name: repo_name.clone(),
        default_branch: default_branch.clone(),
        source_path: local_path.clone(),
        workspace_root: workspace_root.to_string_lossy().to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    sqlx::query(
        r#"
        INSERT INTO local_repositories (id, name, default_branch, source_path, workspace_root, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
        "#,
    )
    .bind(&repository.id)
    .bind(&repository.name)
    .bind(&repository.default_branch)
    .bind(&repository.source_path)
    .bind(&repository.workspace_root)
    .bind(&repository.created_at)
    .execute(pool)
    .await?;

    let thread = create_initial_thread(repo_id, &base_repo_path, &workspace_root, pool).await?;

    Ok(AddLocalRepositoryResponse {
        repository,
        thread,
    })
}
