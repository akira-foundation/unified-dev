use serde::Serialize;
use tauri::State;

use crate::app::support::error::{AppError, AppResult};
use crate::providers::dto::{BranchDto, IssueDto, PullRequestDto};
use crate::state::AppState;

#[derive(Debug, Serialize)]
pub struct ThreadSourceContext {
    pub organization_id: String,
    pub repo_name: String,
}

pub async fn resolve_context(repo_id: &str, state: &State<'_, AppState>) -> AppResult<ThreadSourceContext> {
    let row = sqlx::query_as::<_, (String, String, Option<String>, String)>(
        "SELECT name, source_path, remote_url, workspace_root FROM local_repositories WHERE id = ? LIMIT 1",
    )
    .bind(repo_id)
    .fetch_optional(&state.db_pool)
    .await?;

    let (repo_name, source_path, remote_url, workspace_root) = row.ok_or_else(|| {
        AppError::Internal(format!("Repository '{}' not found", repo_id))
    })?;

    let base_repo_path = std::path::Path::new(&workspace_root).join("repo");
    let remote_candidate = remote_url
        .or_else(|| crate::app::repos::git::get_remote_url(&base_repo_path, "origin"))
        .or_else(|| crate::app::repos::git::get_remote_url(std::path::Path::new(&source_path), "origin"))
        .unwrap_or(source_path);

    let (owner, normalized_repo_name) = parse_github_remote(&remote_candidate).ok_or_else(|| {
        AppError::Internal("Repository is not linked to a supported GitHub remote".to_string())
    })?;

    let row = sqlx::query_as::<_, (String,)>(
        "SELECT organization_id FROM organization_repos WHERE owner = ? AND repo_name = ? AND is_selected = 1 LIMIT 1",
    )
    .bind(&owner)
    .bind(&normalized_repo_name)
    .fetch_optional(&state.db_pool)
    .await?;

    let (organization_id,) = row.ok_or_else(|| {
        AppError::Internal(
            "This repository must be linked to an organization before using issue, pull request, or branch pickers."
                .to_string(),
        )
    })?;

    Ok(ThreadSourceContext {
        organization_id,
        repo_name,
    })
}

pub async fn get_provider_login(repo_id: String, state: State<'_, AppState>) -> AppResult<Option<String>> {
    let context = resolve_context(&repo_id, &state).await?;

    let row = sqlx::query_as::<_, (Option<String>,)>(
        "SELECT p.account_login FROM organizations o LEFT JOIN providers p ON p.id = o.provider_id WHERE o.id = ? LIMIT 1",
    )
    .bind(&context.organization_id)
    .fetch_optional(&state.db_pool)
    .await?;

    Ok(row.and_then(|(login,)| login))
}

pub async fn list_issues(repo_id: String, state: State<'_, AppState>) -> AppResult<Vec<IssueDto>> {
    let context = resolve_context(&repo_id, &state).await?;
    crate::app::issues::list(state, context.organization_id, context.repo_name, Some("all_open".to_string()), None)
        .await
        .map_err(AppError::Internal)
}

pub async fn list_pull_requests(repo_id: String, state: State<'_, AppState>) -> AppResult<Vec<PullRequestDto>> {
    let context = resolve_context(&repo_id, &state).await?;
    crate::app::orgs::pull_requests::list(state, context.organization_id, context.repo_name, None, None)
        .await
        .map_err(AppError::Internal)
}

pub async fn list_branches(repo_id: String, state: State<'_, AppState>) -> AppResult<Vec<BranchDto>> {
    let context = resolve_context(&repo_id, &state).await?;
    crate::app::orgs::branches::list(state, context.organization_id, context.repo_name)
        .await
        .map_err(AppError::Internal)
}

fn parse_github_remote(remote: &str) -> Option<(String, String)> {
    let trimmed = remote.trim().trim_end_matches('/').trim_end_matches(".git");

    let path = if let Some(value) = trimmed.strip_prefix("https://github.com/") {
        value
    } else if let Some(value) = trimmed.strip_prefix("http://github.com/") {
        value
    } else if let Some(value) = trimmed.strip_prefix("git@github.com:") {
        value
    } else {
        return None;
    };

    let mut parts = path.split('/');
    let owner = parts.next()?.trim();
    let repo = parts.next()?.trim();

    if owner.is_empty() || repo.is_empty() {
        return None;
    }

    Some((owner.to_string(), repo.to_string()))
}
