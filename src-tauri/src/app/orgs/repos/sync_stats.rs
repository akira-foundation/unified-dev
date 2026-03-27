use tauri::State;

use crate::state::AppState;

pub async fn sync_stats(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    let repos = sqlx::query_as::<_, crate::database::records::OrganizationRepoSummary>(
        "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
    )
    .bind(&organization_id)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    if repos.is_empty() {
        return Ok(());
    }

    let provider = match crate::app::orgs::resolve_provider::resolve_provider_for_org(&state, &organization_id).await {
        Ok(p) => p,
        Err(_) => return Ok(()),
    };

    let unique_owners: Vec<String> = {
        let mut seen = std::collections::HashSet::new();
        repos.iter().filter_map(|r| seen.insert(r.owner.clone()).then(|| r.owner.clone())).collect()
    };

    let mut repo_meta: std::collections::HashMap<String, (String, String)> = std::collections::HashMap::new();
    for owner in unique_owners {
        if let Ok(provider_repos) = provider.list_organization_repositories(&owner).await {
            for pr in provider_repos {
                repo_meta.insert(pr.name.clone(), (pr.default_branch.clone(), pr.visibility.clone()));
            }
        }
    }

    for repo in &repos {
        let (default_branch, visibility) = repo_meta
            .get(&repo.repo_name)
            .cloned()
            .unwrap_or_else(|| (repo.default_branch.clone(), repo.visibility.clone()));

        let open_prs_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM pull_requests WHERE org_id = ? AND repo_name = ? AND state = 'open'",
        )
        .bind(&organization_id)
        .bind(&repo.repo_name)
        .fetch_one(&state.db_pool)
        .await
        .unwrap_or(0);

        let _ = sqlx::query(
            "UPDATE organization_repos SET default_branch = ?, visibility = ?, open_prs_count = ? WHERE organization_id = ? AND repo_name = ?",
        )
        .bind(&default_branch)
        .bind(&visibility)
        .bind(open_prs_count)
        .bind(&organization_id)
        .bind(&repo.repo_name)
        .execute(&state.db_pool)
        .await;
    }

    Ok(())
}
