use tauri::State;

use crate::providers::types::PrMergeStrategy;
use crate::state::AppState;

pub async fn merge_pr(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, strategy: PrMergeStrategy) -> Result<(), String> {
    let (owner, provider) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .merge_pull_request(&owner, &repo_name, pr_number, strategy)
        .await
        .map_err(|e| e.to_string())
}
