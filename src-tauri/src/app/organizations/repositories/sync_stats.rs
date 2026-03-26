use tauri::State;

use crate::providers::types::PullRequestState;
use crate::state::AppState;

pub async fn sync_stats(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    let repos = state
        .organization_repos
        .list_selected_by_org(&organization_id)
        .await
        .map_err(|e| e.to_string())?;

    if repos.is_empty() {
        return Ok(());
    }

    let provider = match crate::app::organizations::resolve_provider::resolve_provider_for_org(&state, &organization_id).await {
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

    let futures: Vec<_> = repos
        .iter()
        .map(|repo| {
            let provider = provider.clone();
            let owner = repo.owner.clone();
            let repo_name = repo.repo_name.clone();
            let (default_branch, visibility) = repo_meta
                .get(&repo_name)
                .cloned()
                .unwrap_or_else(|| (repo.default_branch.clone(), repo.visibility.clone()));
            async move {
                let open_prs_count = provider
                    .list_pull_requests(&owner, &repo_name)
                    .await
                    .map(|prs| prs.iter().filter(|pr| matches!(pr.state, PullRequestState::Open)).count() as i64)
                    .unwrap_or(0);
                (repo_name, default_branch, visibility, open_prs_count)
            }
        })
        .collect();

    let results = futures_util::future::join_all(futures).await;

    for (repo_name, default_branch, visibility, open_prs_count) in results {
        let _ = state
            .organization_repos
            .update_repo_stats(&organization_id, &repo_name, &default_branch, &visibility, open_prs_count)
            .await;
    }

    Ok(())
}
