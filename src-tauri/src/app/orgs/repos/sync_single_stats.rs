use tauri::State;

use crate::state::AppState;

pub async fn sync_single_stats(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
) -> Result<(), String> {
    let repos = sqlx::query_as::<_, crate::database::records::OrganizationRepoSummary>(
        "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, is_fork, fork_owner, fork_repo, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
    )
    .bind(&organization_id)
    .fetch_all(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())?;

    let Some(repo) = repos.iter().find(|r| r.repo_name == repo_name) else {
        return Ok(());
    };

    let owner = repo.owner.clone();
    let current_default_branch = repo.default_branch.clone();
    let current_visibility = repo.visibility.clone();
    let current_is_fork = repo.is_fork;
    let current_fork_owner = repo.fork_owner.clone();
    let current_fork_repo = repo.fork_repo.clone();

    let (provider, is_personal_owner) =
        match crate::app::orgs::resolve_provider::resolve_provider_for_repo_owner(
            &state,
            &organization_id,
            &owner,
        )
        .await
        {
            Ok(p) => p,
            Err(_) => return Ok(()),
        };

    let provider_repos = if is_personal_owner {
        provider.list_repositories().await
    } else {
        provider.list_organization_repositories(&owner).await
    };

    let (default_branch, visibility, is_fork, fork_owner, fork_repo) = provider_repos
        .ok()
        .and_then(|repos| repos.into_iter().find(|r| r.name == repo_name))
        .map(|r| {
            (
                r.default_branch,
                r.visibility,
                r.is_fork,
                r.fork_owner,
                r.fork_repo,
            )
        })
        .unwrap_or((
            current_default_branch,
            current_visibility,
            current_is_fork,
            current_fork_owner,
            current_fork_repo,
        ));

    let open_prs_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM pull_requests WHERE org_id = ? AND repo_name = ? AND state = 'open'",
    )
    .bind(&organization_id)
    .bind(&repo_name)
    .fetch_one(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .unwrap_or(0);

    let _ = sqlx::query(
        "UPDATE organization_repos SET default_branch = ?, visibility = ?, open_prs_count = ?, is_fork = ?, fork_owner = ?, fork_repo = ? WHERE organization_id = ? AND repo_name = ?",
    )
    .bind(&default_branch)
    .bind(&visibility)
    .bind(open_prs_count)
    .bind(is_fork)
    .bind(&fork_owner)
    .bind(&fork_repo)
    .bind(&organization_id)
    .bind(&repo_name)
    .execute(&state.pool().await.map_err(|e| e.to_string())?)
    .await;

    Ok(())
}
