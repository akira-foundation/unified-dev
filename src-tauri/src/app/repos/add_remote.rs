use std::path::Path;

use uuid::Uuid;

use crate::app::repos::git;
use crate::app::repos::providers;
use crate::app::repos::types::{AddLocalRepositoryResponse, LocalRepository};
use crate::app::support::error::{AppError, AppResult};
use crate::app::threads::create_with_paths;
use crate::state::AppState;

pub async fn add_remote(
    url: String,
    state: tauri::State<'_, AppState>,
) -> AppResult<AddLocalRepositoryResponse> {
    let pool = &state.pool().await?;

    let (provider, nwo) = providers::detect(&url).ok_or_else(|| {
        AppError::Internal(
            "Unsupported repository URL. Only GitHub, GitLab, and Bitbucket URLs are supported."
                .to_string(),
        )
    })?;

    let repo_name = git::repo_name_from_url(&url).ok_or_else(|| {
        AppError::Internal("Could not parse repository name from URL.".to_string())
    })?;

    let home_dir = dirs::home_dir()
        .ok_or_else(|| AppError::Internal("Could not find home directory".to_string()))?;
    let workspace_root = home_dir
        .join(".unifieddev")
        .join("workspaces")
        .join(&repo_name);
    if !workspace_root.exists() {
        std::fs::create_dir_all(&workspace_root).map_err(AppError::Io)?;
    }

    let base_repo_path = workspace_root.join("repo");
    if !git::is_valid_clone(&base_repo_path) {
        if base_repo_path.exists() {
            std::fs::remove_dir_all(&base_repo_path).map_err(AppError::Io)?;
        }
        provider.clone(&nwo, &base_repo_path)?;
    }

    let default_branch = git::get_default_branch(&base_repo_path)?;

    let customer_id = crate::app::auth::current_customer_id(pool).await;
    let existing: Option<(String,)> = sqlx::query_as(
        "SELECT id FROM local_repositories WHERE source_path = ? AND customer_id = ? LIMIT 1",
    )
    .bind(&url)
    .bind(&customer_id)
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
        remote_url: Some(url.clone()),
        workspace_root: workspace_root.to_string_lossy().to_string(),
        created_at: chrono::Utc::now().to_rfc3339(),
    };

    sqlx::query(
        "INSERT INTO local_repositories (id, name, default_branch, source_path, remote_url, workspace_root, created_at, customer_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&repository.id)
    .bind(&repository.name)
    .bind(&repository.default_branch)
    .bind(&repository.source_path)
    .bind(&repository.remote_url)
    .bind(&repository.workspace_root)
    .bind(&repository.created_at)
    .bind(&customer_id)
    .execute(pool)
    .await?;

    let thread = create_with_paths(
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
