use std::sync::Arc;

use crate::providers::traits::VcsProvider;
use crate::state::AppState;

pub async fn get_provider(
    state: &AppState,
    org_id: &str,
) -> Result<Arc<dyn VcsProvider>, String> {
    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(org_id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?
    .ok_or_else(|| "Organization has no provider".to_string())?;

    let credentials = crate::app::providers::credentials::credentials(state, &provider_id)
        .await
        .map_err(|e| e.to_string())?;

    state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|e| e.to_string())
}

pub async fn resolve_owner(state: &AppState, org_id: &str, repo_name: &str) -> Result<String, String> {
    sqlx::query_scalar::<_, String>(
        "SELECT owner FROM organization_repos WHERE organization_id = ? AND repo_name = ? LIMIT 1",
    )
    .bind(org_id)
    .bind(repo_name)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}

pub async fn resolve_provider_and_owner(
    state: &AppState,
    org_id: &str,
    repo_name: &str,
) -> Result<(Arc<dyn VcsProvider>, String), String> {
    let provider = get_provider(state, org_id).await?;
    let owner = resolve_owner(state, org_id, repo_name).await?;
    Ok((provider, owner))
}
