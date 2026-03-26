use tauri::State;

use crate::providers::dto::PrCommentDto;
use crate::state::AppState;

pub async fn post_comment(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, body: String) -> Result<PrCommentDto, String> {
    let (owner, provider) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let comment = provider
        .post_pull_request_comment(&owner, &repo_name, pr_number, &body)
        .await
        .map_err(|e| e.to_string())?;
    Ok(PrCommentDto::from(comment))
}
