use tauri::State;

use crate::providers::enums::PrReviewEvent;
use crate::state::AppState;

pub async fn submit_review(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, event: PrReviewEvent, body: Option<String>) -> Result<(), String> {
    let (owner, repo_name, provider, _) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .submit_pull_request_review(&owner, &repo_name, pr_number, event, body.as_deref())
        .await
        .map_err(|e| e.to_string())
}
