use tauri::State;

use crate::state::AppState;

pub async fn delete_comment(state: State<'_, AppState>, organization_id: String, repo_name: String, comment_id: String) -> Result<(), String> {
    let (owner, repo_name, provider, _) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .delete_pull_request_comment(&owner, &repo_name, &comment_id)
        .await
        .map_err(|e| e.to_string())
}
