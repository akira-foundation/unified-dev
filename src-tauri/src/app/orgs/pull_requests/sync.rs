use tauri::State;

use crate::providers::enums::PullRequestState;
use crate::providers::dto::PullRequestDto;
use crate::state::AppState;

pub async fn sync(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    owner: Option<String>,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<PullRequestDto>, String> {
    let _ = owner;
    let (owner, provider) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let prs = provider
        .list_pull_requests(&owner, &repo_name)
        .await
        .map_err(|e| e.to_string())?;
    let scope = scope.unwrap_or_else(|| "mine_or_review_requested".to_string());
    let login = current_login.map(|value| value.to_lowercase());
    Ok(prs
        .into_iter()
        .filter(|pr| matches!(pr.state, PullRequestState::Open))
        .filter(|pr| match scope.as_str() {
            "all_open" => true,
            _ => login.as_ref().map(|current| {
                pr.author.as_ref().map(|author| author.to_lowercase() == *current).unwrap_or(false)
                    || pr.reviewers.iter().any(|reviewer| reviewer.to_lowercase() == *current)
            }).unwrap_or(true),
        })
        .map(PullRequestDto::from)
        .collect())
}
