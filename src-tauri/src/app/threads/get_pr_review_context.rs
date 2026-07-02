use serde::Serialize;
use tauri::State;

use crate::providers::dto::PullRequestDto;
use crate::state::AppState;

#[derive(Debug, Serialize)]
pub struct ActiveRepoDto {
    pub name: String,
    pub owner: String,
    pub organization_id: String,
}

#[derive(Debug, Serialize)]
pub struct PrReviewContext {
    pub repo: ActiveRepoDto,
    pub pr: PullRequestDto,
}

fn parse_owner(source_path: &str) -> Option<String> {
    let url = source_path.trim_end_matches('/').trim_end_matches(".git");
    let parts: Vec<&str> = url.split('/').collect();
    if parts.len() < 2 {
        return None;
    }
    Some(parts[parts.len() - 2].to_string())
}

pub async fn get_pr_review_context(
    thread_id: String,
    state: State<'_, AppState>,
) -> Result<PrReviewContext, String> {
    let pool = &state.db_pool;

    let row: Option<(String, String, String)> = sqlx::query_as(
        "SELECT lr.name, lr.source_path, t.pr_url
         FROM threads t
         JOIN local_repositories lr ON lr.id = t.repo_id
         WHERE t.id = ?
         LIMIT 1",
    )
    .bind(&thread_id)
    .fetch_optional(pool)
    .await
    .map_err(|e| e.to_string())?;

    let (repo_name, source_path, pr_url) =
        row.ok_or_else(|| "Thread not found or has no PR".to_string())?;

    if pr_url.is_empty() {
        return Err("Thread has no PR".to_string());
    }

    let owner = parse_owner(&source_path)
        .ok_or_else(|| "Could not parse owner from source_path".to_string())?;

    let org_row: Option<(String,)> = sqlx::query_as(
        "SELECT organization_id FROM organization_repos WHERE repo_name = ? LIMIT 1",
    )
    .bind(&repo_name)
    .fetch_optional(pool)
    .await
    .map_err(|e| e.to_string())?;

    let organization_id = org_row
        .map(|(id,)| id)
        .ok_or_else(|| "Repository is not linked to any organization".to_string())?;

    let cached = crate::app::orgs::list_repo_pull_requests(
        state.clone(),
        organization_id.clone(),
        repo_name.clone(),
        Some("all".to_string()),
        None,
    )
    .await?;

    let pr = match cached.into_iter().find(|p| p.url == pr_url) {
        Some(pr) => pr,
        None => {
            let synced = crate::app::orgs::sync_pull_requests(
                state,
                organization_id.clone(),
                repo_name.clone(),
                Some(owner.clone()),
                Some("all".to_string()),
                None,
            )
            .await?;
            synced
                .into_iter()
                .find(|p| p.url == pr_url)
                .ok_or_else(|| "PR not found after syncing repository".to_string())?
        }
    };

    Ok(PrReviewContext {
        repo: ActiveRepoDto {
            name: repo_name,
            owner,
            organization_id,
        },
        pr,
    })
}

#[cfg(test)]
mod tests {
    use super::parse_owner;

    #[test]
    fn parses_owner_from_https_url() {
        assert_eq!(parse_owner("https://github.com/acme/repo.git"), Some("acme".to_string()));
    }

    #[test]
    fn parses_owner_ignoring_trailing_slash() {
        assert_eq!(parse_owner("https://github.com/acme/repo/"), Some("acme".to_string()));
    }

    #[test]
    fn returns_none_without_owner_segment() {
        assert_eq!(parse_owner("repo"), None);
    }
}
