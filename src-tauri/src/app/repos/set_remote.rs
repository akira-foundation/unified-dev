use crate::app::support::error::{AppError, AppResult};

pub async fn set_remote(repo_id: String, remote_url: String, pool: &sqlx::SqlitePool) -> AppResult<()> {
    let normalized = normalize_github_remote(&remote_url)?;

    sqlx::query("UPDATE local_repositories SET remote_url = ? WHERE id = ?")
        .bind(&normalized)
        .bind(&repo_id)
        .execute(pool)
        .await?;

    Ok(())
}

fn normalize_github_remote(value: &str) -> AppResult<String> {
    let trimmed = value.trim();

    let is_https = trimmed.starts_with("https://github.com/") || trimmed.starts_with("http://github.com/");
    let is_ssh = trimmed.starts_with("git@github.com:");

    if !is_https && !is_ssh {
        return Err(AppError::Internal(
            "Remote must be a GitHub SSH or HTTPS URL.".to_string(),
        ));
    }

    Ok(trimmed.trim_end_matches('/').to_string())
}
