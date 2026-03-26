use tauri::State;

use crate::providers::types::PrCommentDto;
use crate::state::AppState;

pub async fn get_comments(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64) -> Result<Vec<PrCommentDto>, String> {
    let (owner, provider) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let comments = provider
        .get_pull_request_comments(&owner, &repo_name, pr_number)
        .await
        .map_err(|e| e.to_string())?;
    Ok(comments.into_iter().map(PrCommentDto::from).collect())
}
