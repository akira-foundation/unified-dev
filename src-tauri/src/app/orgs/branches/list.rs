use tauri::State;

use crate::providers::dto::BranchDto;
use crate::state::AppState;

pub async fn list(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
) -> Result<Vec<BranchDto>, String> {
    let (_, _, provider, _) =
        crate::app::orgs::pull_requests::resolve_provider::resolve_pr_provider(
            &state,
            &organization_id,
            &repo_name,
        )
        .await?;
    let owner = sqlx::query_scalar::<_, String>(
        "SELECT owner FROM organization_repos WHERE organization_id = ? AND repo_name = ? LIMIT 1",
    )
    .bind(&organization_id)
    .bind(&repo_name)
    .fetch_one(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())?;
    let branches = provider
        .list_branches(&owner, &repo_name)
        .await
        .map_err(|e| e.to_string())?;
    Ok(branches.into_iter().map(BranchDto::from).collect())
}
