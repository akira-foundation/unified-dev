use std::sync::Arc;

use crate::app::concerns::VcsProvider;
use crate::database::records::OrganizationRepoSummary;
use crate::state::AppState;

pub async fn resolve_pr_provider(
    state: &AppState,
    organization_id: &str,
    repo_name: &str,
) -> Result<(String, String, Arc<dyn VcsProvider>, bool), String> {
    let repos = sqlx::query_as::<_, OrganizationRepoSummary>(
        "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, is_fork, fork_owner, fork_repo, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
    )
    .bind(organization_id)
    .fetch_all(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())?;

    let repo = repos
        .iter()
        .find(|r| r.repo_name == repo_name)
        .ok_or_else(|| format!("repository '{}' not found", repo_name))?;

    let (effective_owner, effective_repo, is_upstream) = match (&repo.fork_owner, &repo.fork_repo) {
        (Some(fo), Some(fr)) if repo.is_fork => (fo.clone(), fr.clone(), true),
        _ if repo.is_fork => {
            let resolved = crate::app::orgs::resolve_provider::fetch_and_persist_github_parent(
                state,
                organization_id,
                &repo.owner,
                repo_name,
            )
            .await;
            match resolved {
                Some((fo, fr)) => (fo, fr, true),
                None => (repo.owner.clone(), repo.repo_name.clone(), false),
            }
        }
        _ => (repo.owner.clone(), repo.repo_name.clone(), false),
    };

    let (provider, _) = crate::app::orgs::resolve_provider::resolve_provider_for_repo_owner(
        state,
        organization_id,
        &effective_owner,
    )
    .await?;

    Ok((effective_owner, effective_repo, provider, is_upstream))
}
