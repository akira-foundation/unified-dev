use std::path::Path;

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::{AppError, AppResult};
use crate::workspaces::git;

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

/// Entry point used by the Tauri command — looks up repo paths from the DB.
pub async fn create_thread(repo_id: String, pool: &sqlx::SqlitePool) -> AppResult<ThreadConfig> {
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

    create_with_paths(repo_id, &base_repo_path, &workspace_root, Path::new(&source_path), None, pool).await
}

/// Called by workspaces/local.rs and workspaces/remote.rs when paths are already known.
pub async fn create_with_paths(
    repo_id: String,
    base_repo_path: &Path,
    workspace_root: &Path,
    source_path: &Path,
    remote_url_override: Option<String>,
    pool: &sqlx::SqlitePool,
) -> AppResult<ThreadConfig> {
    let thread_uuid = Uuid::new_v4();
    let thread_id = thread_uuid.to_string().to_uppercase();
    let thread_branch = format!("thread/{}", thread_id);
    let title = generate_thread_name(thread_uuid.as_u64_pair().0);
    let workspace_path = workspace_root.join(&thread_id);

    git::clone_repository(base_repo_path, &workspace_path)?;

    // Propagate the real GitHub remote to the workspace so that `git push origin`
    // reaches GitHub rather than the local base clone.
    let github_url = remote_url_override
        .or_else(|| git::get_remote_url(source_path, "origin"));
    if let Some(url) = github_url {
        if git::is_github_url(&url) {
            let _ = git::set_remote_url(&workspace_path, "origin", &url);
        }
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

fn generate_thread_name(seed: u64) -> String {
    const ADJECTIVES: &[&str] = &[
        "gentle", "silver", "amber", "crimson", "silent", "hollow", "golden",
        "swift", "ancient", "bright", "calm", "dark", "eager", "faint",
        "grand", "heavy", "idle", "jade", "keen", "lean", "misty", "noble",
        "pale", "quiet", "rough", "sharp", "tall", "vast", "warm", "young",
    ];
    const NOUNS: &[&str] = &[
        "river", "hawk", "pine", "stone", "cloud", "flame", "ridge",
        "creek", "dawn", "dusk", "field", "forge", "gate", "grove",
        "hill", "isle", "lake", "marsh", "peak", "plain", "reef",
        "crest", "shade", "shore", "slope", "storm", "vale", "wave", "wind", "wood",
    ];
    let adj = ADJECTIVES[(seed as usize) % ADJECTIVES.len()];
    let noun = NOUNS[((seed >> 8) as usize) % NOUNS.len()];
    format!("{}-{}", adj, noun)
}
