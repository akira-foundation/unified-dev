use tauri::State;

use crate::providers::enums::PullRequestState;
use crate::state::AppState;

pub async fn sync_single_stats(state: State<'_, AppState>, organization_id: String, repo_name: String) -> Result<(), String> {
    let repos = sqlx::query_as::<_, crate::database::records::OrganizationRepoSummary>(
        "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
    )
    .bind(&organization_id)
    .fetch_all(&state.db_pool)
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

    let _ = sqlx::query(
        "UPDATE organization_repos SET default_branch = ?, visibility = ?, open_prs_count = ? WHERE organization_id = ? AND repo_name = ?",
    )
    .bind(&default_branch)
    .bind(&visibility)
    .bind(open_prs_count)
    .bind(&organization_id)
    .bind(&repo_name)
    .execute(&state.db_pool)
    .await;

    Ok(())
}
