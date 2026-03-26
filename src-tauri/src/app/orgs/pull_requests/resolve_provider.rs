use std::sync::Arc;

use crate::app::orgs::resolve_provider::resolve_provider_for_org;
use crate::app::concerns::VcsProvider;
use crate::database::records::OrganizationRepoSummary;
use crate::state::AppState;

pub async fn resolve_pr_provider(
    state: &AppState,
    organization_id: &str,
    repo_name: &str,
) -> Result<(String, Arc<dyn VcsProvider>), String> {
    let repos = sqlx::query_as::<_, OrganizationRepoSummary>(
        "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
    )
    .bind(organization_id)
    .fetch_all(&state.db_pool)
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
