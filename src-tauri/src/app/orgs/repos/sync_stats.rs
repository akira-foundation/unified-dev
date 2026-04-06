use tauri::State;

use crate::state::AppState;

struct RepoMeta {
    default_branch: String,
    visibility: String,
    is_fork: bool,
    fork_owner: Option<String>,
    fork_repo: Option<String>,
}

pub async fn sync_stats(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    let repos = sqlx::query_as::<_, crate::database::records::OrganizationRepoSummary>(
        "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, is_fork, fork_owner, fork_repo, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
    )
    .bind(&organization_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    if repos.is_empty() {
        return Ok(());
    }

    let unique_owners: Vec<String> = {
        let mut seen = std::collections::HashSet::new();
        repos.iter().filter_map(|r| seen.insert(r.owner.clone()).then(|| r.owner.clone())).collect()
    };

    let mut repo_meta: std::collections::HashMap<String, RepoMeta> = std::collections::HashMap::new();
    for owner in unique_owners {
        let Ok((provider, is_personal_owner)) = crate::app::orgs::resolve_provider::resolve_provider_for_repo_owner(&state, &organization_id, &owner).await else {
            continue;
        };

        let provider_repos_result = if is_personal_owner {
            provider.list_repositories().await
        } else {
            provider.list_organization_repositories(&owner).await
        };

        if let Ok(provider_repos) = provider_repos_result {
            for pr in provider_repos {
                repo_meta.insert(pr.name.clone(), RepoMeta {
                    default_branch: pr.default_branch,
                    visibility: pr.visibility,
                    is_fork: pr.is_fork,
                    fork_owner: pr.fork_owner,
                    fork_repo: pr.fork_repo,
                });
            }
        }
    }

    for repo in &repos {
        let meta = repo_meta.get(&repo.repo_name);
        let default_branch = meta.map(|m| m.default_branch.as_str()).unwrap_or(&repo.default_branch).to_string();
        let visibility = meta.map(|m| m.visibility.as_str()).unwrap_or(&repo.visibility).to_string();
        let is_fork = meta.map(|m| m.is_fork).unwrap_or(repo.is_fork);
        let fork_owner = meta.and_then(|m| m.fork_owner.clone()).or_else(|| repo.fork_owner.clone());
        let fork_repo = meta.and_then(|m| m.fork_repo.clone()).or_else(|| repo.fork_repo.clone());

        let open_prs_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM pull_requests WHERE org_id = ? AND repo_name = ? AND state = 'open'",
        )
        .bind(&organization_id)
        .bind(&repo.repo_name)
        .fetch_one(&state.db_pool)
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
        .bind(&repo.repo_name)
        .execute(&state.db_pool)
        .await;
    }

    Ok(())
}
