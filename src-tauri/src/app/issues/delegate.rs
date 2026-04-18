use std::path::Path;

use uuid::Uuid;

use crate::app::repos::git;
use crate::app::repos::types::{AddLocalRepositoryResponse, LocalRepository};
use crate::app::threads::create::ThreadConfig;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

pub async fn delegate(
    state: &AppState,
    org_id: String,
    repo_name: String,
    issue_title: String,
) -> AppResult<AddLocalRepositoryResponse> {
    let pool = &state.db_pool;

    let owner = crate::app::issues::resolve_provider::resolve_owner(state, &org_id, &repo_name)
        .await
        .map_err(AppError::Internal)?;

    let clone_url = format!("https://github.com/{}/{}", owner, repo_name);

    let thread_title = build_thread_title(&issue_title, &repo_name, pool).await?;

    let existing: Option<(String, String, String)> = sqlx::query_as(
        "SELECT id, name, workspace_root FROM local_repositories WHERE source_path = ? LIMIT 1",
    )
    .bind(&clone_url)
    .fetch_optional(pool)
    .await?;

    if let Some((repo_id, name, workspace_root)) = existing {
        let workspace_root = std::path::PathBuf::from(&workspace_root);
        let base_repo_path = workspace_root.join("repo");

        if !base_repo_path.exists() {
            return Err(AppError::Internal("Base repository clone not found".to_string()));
        }

        let thread = create_thread_with_title(
            repo_id.clone(),
            &base_repo_path,
            &workspace_root,
            &clone_url,
            thread_title,
            pool,
        )
        .await?;

        let repository = LocalRepository {
            id: repo_id,
            name,
            default_branch: String::new(),
            source_path: clone_url.clone(),
            remote_url: Some(clone_url.clone()),
            workspace_root: workspace_root.to_string_lossy().to_string(),
            created_at: String::new(),
        };

        Ok(AddLocalRepositoryResponse { repository, thread })
    } else {
        let home_dir = dirs::home_dir()
            .ok_or_else(|| AppError::Internal("Could not find home directory".to_string()))?;
        let workspace_root = home_dir.join(".unifieddev").join("workspaces").join(&repo_name);
        if !workspace_root.exists() {
            std::fs::create_dir_all(&workspace_root).map_err(AppError::Io)?;
        }
        let base_repo_path = workspace_root.join("repo");
        if !base_repo_path.exists() {
            git::clone_from_url(&clone_url, &base_repo_path)?;
        }
        let default_branch = git::get_default_branch(&base_repo_path)?;

        let repo_id = Uuid::new_v4().to_string().to_uppercase();
        let repository = LocalRepository {
            id: repo_id.clone(),
            name: repo_name.clone(),
            default_branch,
            source_path: clone_url.clone(),
            remote_url: Some(clone_url.clone()),
            workspace_root: workspace_root.to_string_lossy().to_string(),
            created_at: chrono::Utc::now().to_rfc3339(),
        };

        sqlx::query(
            "INSERT INTO local_repositories (id, name, default_branch, source_path, remote_url, workspace_root, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&repository.id)
        .bind(&repository.name)
        .bind(&repository.default_branch)
        .bind(&repository.source_path)
        .bind(&repository.remote_url)
        .bind(&repository.workspace_root)
        .bind(&repository.created_at)
        .execute(pool)
        .await?;

        let thread = create_thread_with_title(
            repo_id,
            &base_repo_path,
            &workspace_root,
            &clone_url,
            thread_title,
            pool,
        )
        .await?;

        Ok(AddLocalRepositoryResponse { repository, thread })
    }
}

async fn build_thread_title(
    issue_title: &str,
    repo_name: &str,
    pool: &sqlx::SqlitePool,
) -> AppResult<String> {
    let base = to_kebab_case(issue_title);

    let repo_id: Option<(String,)> =
        sqlx::query_as("SELECT id FROM local_repositories WHERE name = ? LIMIT 1")
            .bind(repo_name)
            .fetch_optional(pool)
            .await?;

    let Some((repo_id,)) = repo_id else {
        return Ok(base);
    };

    let existing_titles: Vec<(String,)> =
        sqlx::query_as("SELECT title FROM threads WHERE repo_id = ?")
            .bind(&repo_id)
            .fetch_all(pool)
            .await?;

    let titles: std::collections::HashSet<String> =
        existing_titles.into_iter().map(|(t,)| t).collect();

    if !titles.contains(&base) {
        return Ok(base);
    }

    let mut suffix = 2u32;
    loop {
        let candidate = format!("{}-{}", base, suffix);
        if !titles.contains(&candidate) {
            return Ok(candidate);
        }
        suffix += 1;
    }
}

fn to_kebab_case(s: &str) -> String {
    s.to_lowercase()
        .chars()
        .map(|c| if c.is_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .split('-')
        .filter(|p| !p.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

async fn create_thread_with_title(
    repo_id: String,
    base_repo_path: &Path,
    workspace_root: &Path,
    clone_url: &str,
    title: String,
    pool: &sqlx::SqlitePool,
) -> AppResult<ThreadConfig> {
    let thread_uuid = Uuid::new_v4();
    let thread_id = thread_uuid.to_string().to_uppercase();
    let thread_branch = format!("thread/{}", thread_id);
    let workspace_path = workspace_root.join(&thread_id);

    git::clone_repository(base_repo_path, &workspace_path)?;

    if git::is_github_url(clone_url) {
        let _ = git::set_remote_url(&workspace_path, "origin", clone_url);
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
