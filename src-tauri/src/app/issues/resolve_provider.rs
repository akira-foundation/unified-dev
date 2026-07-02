use std::sync::Arc;

use crate::app::concerns::VcsProvider;
use crate::state::AppState;

pub async fn resolve_owner(
    state: &AppState,
    org_id: &str,
    repo_name: &str,
) -> Result<String, String> {
    sqlx::query_scalar::<_, String>(
        "SELECT owner FROM organization_repos WHERE organization_id = ? AND repo_name = ? LIMIT 1",
    )
    .bind(org_id)
    .bind(repo_name)
    .fetch_one(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())
}

pub async fn resolve_provider_and_owner(
    state: &AppState,
    org_id: &str,
    repo_name: &str,
) -> Result<(Arc<dyn VcsProvider>, String), String> {
    let owner = resolve_owner(state, org_id, repo_name).await?;
    let (provider, _) =
        crate::app::orgs::resolve_provider::resolve_provider_for_repo_owner(state, org_id, &owner)
            .await?;
    Ok((provider, owner))
}
