use std::path::Path;

use crate::app::support::error::{AppError, AppResult};

pub async fn link_organization(
    repo_id: String,
    organization_id: String,
    pool: &sqlx::SqlitePool,
) -> AppResult<()> {
    let row = sqlx::query_as::<_, (String, Option<String>, String, String, String)>(
        "SELECT source_path, remote_url, workspace_root, name, default_branch FROM local_repositories WHERE id = ? LIMIT 1",
    )
    .bind(&repo_id)
    .fetch_optional(pool)
    .await?;

    let (source_path, remote_url, workspace_root, _name, default_branch) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    let base_repo_path = Path::new(&workspace_root).join("repo");
    let remote_candidate = remote_url
        .or_else(|| crate::app::repos::git::get_remote_url(&base_repo_path, "origin"))
        .or_else(|| crate::app::repos::git::get_remote_url(Path::new(&source_path), "origin"))
        .unwrap_or(source_path);

    let (owner, repo_name) = parse_github_remote(&remote_candidate)?;

    let existing = sqlx::query(
        "UPDATE organization_repos SET owner = ?, visibility = ?, is_selected = 1, auto_sync = 1, default_branch = ? WHERE organization_id = ? AND repo_name = ?",
    )
    .bind(&owner)
    .bind("private")
    .bind(&default_branch)
    .bind(&organization_id)
    .bind(&repo_name)
    .execute(pool)
    .await?;

    if existing.rows_affected() == 0 {
        sqlx::query(
            "INSERT INTO organization_repos (organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, created_at) VALUES (?, ?, ?, ?, 1, 1, ?, 0, ?)",
        )
        .bind(&organization_id)
        .bind(&owner)
        .bind(&repo_name)
        .bind("private")
        .bind(&default_branch)
        .bind(chrono::Utc::now().to_rfc3339())
        .execute(pool)
        .await?;
    }

    Ok(())
}

fn parse_github_remote(value: &str) -> AppResult<(String, String)> {
    let trimmed = value.trim().trim_end_matches('/').trim_end_matches(".git");

    let path = if let Some(value) = trimmed.strip_prefix("https://github.com/") {
        value
    } else if let Some(value) = trimmed.strip_prefix("http://github.com/") {
        value
    } else if let Some(value) = trimmed.strip_prefix("git@github.com:") {
        value
    } else {
        return Err(AppError::Internal(
            "Repository remote must be a GitHub SSH or HTTPS URL before it can be linked."
                .to_string(),
        ));
    };

    let mut parts = path.split('/');
    let owner = parts.next().unwrap_or_default().trim();
    let repo = parts.next().unwrap_or_default().trim();

    if owner.is_empty() || repo.is_empty() {
        return Err(AppError::Internal("Could not parse owner/repository from remote URL.".to_string()));
    }

    Ok((owner.to_string(), repo.to_string()))
}
