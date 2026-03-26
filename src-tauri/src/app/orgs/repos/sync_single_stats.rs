use tauri::State;

use crate::providers::enums::PullRequestState;
use crate::state::AppState;

pub async fn sync_single_stats(state: State<'_, AppState>, organization_id: String, repo_name: String) -> Result<(), String> {
    let repos = state
        .organization_repos
        .list_selected_by_org(&organization_id)
        .await
        .map_err(|e| e.to_string())?;

    let Some(repo) = repos.iter().find(|r| r.repo_name == repo_name) else {
        return Ok(());
    };

    let owner = repo.owner.clone();
    let current_default_branch = repo.default_branch.clone();
    let current_visibility = repo.visibility.clone();

    let provider = match crate::app::orgs::resolve_provider::resolve_provider_for_org(&state, &organization_id).await {
        Ok(p) => p,
        Err(_) => return Ok(()),
    };

    let (default_branch, visibility) = provider
        .list_organization_repositories(&owner)
        .await
        .ok()
        .and_then(|repos| repos.into_iter().find(|r| r.name == repo_name))
        .map(|r| (r.default_branch, r.visibility))
        .unwrap_or((current_default_branch, current_visibility));

    let open_prs_count = provider
        .list_pull_requests(&owner, &repo_name)
        .await
        .map(|prs| prs.iter().filter(|pr| matches!(pr.state, PullRequestState::Open)).count() as i64)
        .unwrap_or(0);

    let _ = state
        .organization_repos
        .update_repo_stats(&organization_id, &repo_name, &default_branch, &visibility, open_prs_count)
        .await;

    Ok(())
}
