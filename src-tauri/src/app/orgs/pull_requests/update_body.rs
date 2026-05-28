use tauri::State;

use crate::state::AppState;

pub async fn update_body(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64, body: String) -> Result<(), String> {
    let (owner, repo_name, provider, _) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .update_pull_request_body(&owner, &repo_name, pr_number, &body)
        .await
        .map_err(|e| e.to_string())
}
