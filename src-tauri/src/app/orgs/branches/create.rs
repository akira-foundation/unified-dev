use tauri::State;

use crate::providers::dto::BranchDto;
use crate::state::AppState;

pub async fn create(state: State<'_, AppState>, organization_id: String, repo_name: String, branch_name: String, from_sha: String) -> Result<BranchDto, String> {
    let (owner, provider) = crate::app::orgs::pull_requests::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let branch = provider
        .create_branch(&owner, &repo_name, &branch_name, &from_sha)
        .await
        .map_err(|e| e.to_string())?;
    Ok(BranchDto::from(branch))
}
