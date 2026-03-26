use tauri::State;

use crate::providers::types::BranchDto;
use crate::state::AppState;

pub async fn create_repo_branch(state: State<'_, AppState>, organization_id: String, repo_name: String, branch_name: String, from_sha: String) -> Result<BranchDto, String> {
    let (owner, provider) = crate::app::organizations::pull_requests::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let branch = provider
        .create_branch(&owner, &repo_name, &branch_name, &from_sha)
        .await
        .map_err(|e| e.to_string())?;
    Ok(BranchDto::from(branch))
}
