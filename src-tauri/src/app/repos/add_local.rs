use std::path::Path;

use uuid::Uuid;

use crate::app::repos::git;
use crate::app::repos::types::{AddLocalRepositoryResponse, LocalRepository};
use crate::app::threads::create_with_paths;
use crate::state::AppState;
use crate::app::support::error::AppResult;

pub async fn add_local(
    local_path: String,
    state: tauri::State<'_, AppState>,
) -> AppResult<AddLocalRepositoryResponse> {
    let pool = &state.db_pool;
    let source_path = Path::new(&local_path);

    if !git::is_git_repository(source_path) {
        return Err(crate::app::support::error::AppError::Internal("This folder is not a git repository.".to_string()));
    }

    let repo_name = git::get_repository_name(source_path)?;
    let default_branch = git::get_default_branch(source_path)?;
    let remote_url = git::get_remote_url(source_path, "origin");

    let home_dir = dirs::home_dir().ok_or_else(|| crate::app::support::error::AppError::Internal("Could not find home directory".to_string()))?;
    let workspace_root = home_dir.join(".unifieddev").join("workspaces").join(&repo_name);
    if !workspace_root.exists() {
        std::fs::create_dir_all(&workspace_root).map_err(crate::app::support::error::AppError::Io)?;
    }

    let base_repo_path = workspace_root.join("repo");
    if !base_repo_path.exists() {
        git::clone_repository(source_path, &base_repo_path)?;
    }

    let existing: Option<(String,)> = sqlx::query_as("SELECT id FROM local_repositories WHERE source_path = ? LIMIT 1")
        .bind(&local_path)
        .fetch_optional(pool)
        .await?;
    if existing.is_some() {
        return Err(crate::app::support::error::AppError::Internal(format!("The repository '{}' has already been added.", repo_name)));
    }

    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM local_repositories")
        .fetch_one(pool)
        .await?;
    if !crate::app::license::can_add(pool, "repos", count).await? {
        return Err(crate::app::support::error::AppError::FreeTierLimit("repo_limit_reached".to_string()));
    }

    let repo_id = Uuid::new_v4().to_string().to_uppercase();
    let source_path_owned = local_path.clone();
    let repository = LocalRepository {
        id: repo_id.clone(),
        name: repo_name,
        default_branch,
        source_path: local_path,
        remote_url,
        workspace_root: workspace_root.to_string_lossy().to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    sqlx::query("INSERT INTO local_repositories (id, name, default_branch, source_path, remote_url, workspace_root, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
        .bind(&repository.id)
        .bind(&repository.name)
        .bind(&repository.default_branch)
        .bind(&repository.source_path)
        .bind(&repository.remote_url)
        .bind(&repository.workspace_root)
        .bind(&repository.created_at)
        .execute(pool)
        .await?;

    let thread = create_with_paths(repo_id, &base_repo_path, &workspace_root, Path::new(&source_path_owned), repository.remote_url.clone(), pool).await?;

    Ok(AddLocalRepositoryResponse { repository, thread })
}
