use tauri::State;

use crate::state::AppState;

pub async fn delete(state: State<'_, AppState>, organization_id: String, repo_name: String, branch_name: String) -> Result<(), String> {
    let (_, _, provider, _) = crate::app::orgs::pull_requests::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let owner = sqlx::query_scalar::<_, String>(
        "SELECT owner FROM organization_repos WHERE organization_id = ? AND repo_name = ? LIMIT 1",
    )
    .bind(&organization_id)
    .bind(&repo_name)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;
    provider
        .delete_branch(&owner, &repo_name, &branch_name)
        .await
        .map_err(|e| e.to_string())
}
