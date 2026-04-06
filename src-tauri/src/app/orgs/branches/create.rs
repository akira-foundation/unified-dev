use tauri::State;

use crate::providers::dto::BranchDto;
use crate::state::AppState;

pub async fn create(state: State<'_, AppState>, organization_id: String, repo_name: String, branch_name: String, from_sha: String) -> Result<BranchDto, String> {
    let (_, _, provider) = crate::app::orgs::pull_requests::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let owner = sqlx::query_scalar::<_, String>(
        "SELECT owner FROM organization_repos WHERE organization_id = ? AND repo_name = ? LIMIT 1",
    )
    .bind(&organization_id)
    .bind(&repo_name)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;
    let branch = provider
        .create_branch(&owner, &repo_name, &branch_name, &from_sha)
        .await
        .map_err(|e| e.to_string())?;
    Ok(BranchDto::from(branch))
}
