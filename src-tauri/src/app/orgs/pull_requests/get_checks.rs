use tauri::State;

use crate::providers::dto::CiCheckDto;
use crate::state::AppState;

pub async fn get_checks(state: State<'_, AppState>, organization_id: String, repo_name: String, head_sha: String) -> Result<Vec<CiCheckDto>, String> {
    let (owner, repo_name, provider, _) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let checks = provider
        .list_pr_checks(&owner, &repo_name, &head_sha)
        .await
        .map_err(|e| e.to_string())?;
    Ok(checks.into_iter().map(CiCheckDto::from).collect())
}
