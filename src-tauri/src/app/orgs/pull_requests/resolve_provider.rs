use std::sync::Arc;

use crate::app::orgs::resolve_provider::resolve_provider_for_org;
use crate::app::concerns::VcsProvider;
use crate::state::AppState;

pub async fn resolve_pr_provider(
    state: &AppState,
    organization_id: &str,
    repo_name: &str,
) -> Result<(String, Arc<dyn VcsProvider>), String> {
    let repos = state
        .organization_repos
        .list_selected_by_org(organization_id)
        .await
        .map_err(|e| e.to_string())?;

    let repo = repos
        .iter()
        .find(|r| r.repo_name == repo_name)
        .ok_or_else(|| format!("repository '{}' not found", repo_name))?;

    let owner = repo.owner.clone();
    let provider = resolve_provider_for_org(state, organization_id).await?;

    Ok((owner, provider))
}
