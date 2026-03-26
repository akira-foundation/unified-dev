use tauri::State;

use crate::state::AppState;

pub async fn delete(state: State<'_, AppState>, organization_id: String, repo_name: String, branch_name: String) -> Result<(), String> {
    let (owner, provider) = crate::app::organizations::pull_requests::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .delete_branch(&owner, &repo_name, &branch_name)
        .await
        .map_err(|e| e.to_string())
}
