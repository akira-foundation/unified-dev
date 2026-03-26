use tauri::State;

use crate::providers::types::PullRequestState;
use crate::providers::types::PullRequestDto;
use crate::state::AppState;

pub async fn sync(state: State<'_, AppState>, organization_id: String, repo_name: String, owner: Option<String>) -> Result<Vec<PullRequestDto>, String> {
    let _ = owner;
    let (owner, provider) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let prs = provider
        .list_pull_requests(&owner, &repo_name)
        .await
        .map_err(|e| e.to_string())?;
    Ok(prs
        .into_iter()
        .filter(|pr| matches!(pr.state, PullRequestState::Open))
        .map(PullRequestDto::from)
        .collect())
}
