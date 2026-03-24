use futures_util::future::join_all;
use tauri::State;

use crate::db::models::{
    CreateOrganizationInput, OrganizationRepoSummary, OrganizationRepoWithOrg, OrganizationSummary, SelectedRepositoryInput,
    UpdateOrganizationInput,
};
use crate::core::provider::types::{PullRequestDto, PullRequestState};
use crate::state::AppState;

#[tauri::command]
pub async fn create_organization(
    state: State<'_, AppState>,
    input: CreateOrganizationInput,
) -> Result<OrganizationSummary, String> {
    state
        .organization_service
        .create_organization(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_organizations(state: State<'_, AppState>) -> Result<Vec<OrganizationSummary>, String> {
    state
        .organization_service
        .list_organizations()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_organizations_by_provider(
    state: State<'_, AppState>,
    provider_id: String,
) -> Result<Vec<OrganizationSummary>, String> {
    state
        .organization_service
        .list_by_provider(&provider_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn update_organization(
    state: State<'_, AppState>,
    input: UpdateOrganizationInput,
) -> Result<OrganizationSummary, String> {
    state
        .organization_service
        .update_organization(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn delete_organization(state: State<'_, AppState>, organization_id: String) -> Result<(), String> {
    state
        .organization_service
        .delete_organization(&organization_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn save_selected_repositories(
    state: State<'_, AppState>,
    organization_id: String,
    repo_list: Vec<SelectedRepositoryInput>,
) -> Result<(), String> {
    let enriched = enrich_repos_with_pr_counts(&state, &organization_id, repo_list).await;

    state
        .organization_repo_service
        .save_selected_repositories(&organization_id, enriched)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_selected_repositories(
    state: State<'_, AppState>,
    organization_id: String,
) -> Result<Vec<OrganizationRepoSummary>, String> {
    state
        .organization_repo_service
        .list_selected_repositories(&organization_id)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_all_selected_repositories(
    state: State<'_, AppState>,
) -> Result<Vec<OrganizationRepoWithOrg>, String> {
    state
        .organization_repo_service
        .list_all_selected_repositories()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn sync_repository_stats(
    state: State<'_, AppState>,
    organization_id: String,
) -> Result<(), String> {
    let repos = state
        .organization_repo_service
        .list_selected_repositories(&organization_id)
        .await
        .map_err(|e| e.to_string())?;

    if repos.is_empty() {
        return Ok(());
    }

    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(&organization_id)
    .fetch_one(&state.db_pool)
    .await
    .ok()
    .flatten();

    let Some(provider_id) = provider_id else {
        return Ok(());
    };

    let credentials = match state.provider_service.credentials(&provider_id).await {
        Ok(c) => c,
        Err(_) => return Ok(()),
    };

    let provider = match state.provider_factory.create(&credentials.kind, credentials.auth).await {
        Ok(p) => p,
        Err(_) => return Ok(()),
    };

    // Fetch fresh repo metadata (default_branch, visibility) for all unique owners
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

    let results = join_all(futures).await;

    for (repo_name, default_branch, visibility, open_prs_count) in results {
        let _ = state
            .organization_repo_service
            .update_repo_stats(&organization_id, &repo_name, &default_branch, &visibility, open_prs_count)
            .await;
    }

    Ok(())
}

#[tauri::command]
pub async fn sync_single_repo_stats(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
) -> Result<(), String> {
    let repos = state
        .organization_repo_service
        .list_selected_repositories(&organization_id)
        .await
        .map_err(|e| e.to_string())?;

    let Some(repo) = repos.iter().find(|r| r.repo_name == repo_name) else {
        return Ok(());
    };

    let owner = repo.owner.clone();
    let current_default_branch = repo.default_branch.clone();
    let current_visibility = repo.visibility.clone();

    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(&organization_id)
    .fetch_one(&state.db_pool)
    .await
    .ok()
    .flatten();

    let Some(provider_id) = provider_id else {
        return Ok(());
    };

    let credentials = match state.provider_service.credentials(&provider_id).await {
        Ok(c) => c,
        Err(_) => return Ok(()),
    };

    let provider = match state.provider_factory.create(&credentials.kind, credentials.auth).await {
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
        .organization_repo_service
        .update_repo_stats(&organization_id, &repo_name, &default_branch, &visibility, open_prs_count)
        .await;

    Ok(())
}

async fn enrich_repos_with_pr_counts(
    state: &AppState,
    organization_id: &str,
    mut repos: Vec<SelectedRepositoryInput>,
) -> Vec<SelectedRepositoryInput> {
    let provider_id = match sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(organization_id)
    .fetch_one(&state.db_pool)
    .await
    .ok()
    .flatten()
    {
        Some(id) => id,
        None => return repos,
    };

    let credentials = match state.provider_service.credentials(&provider_id).await {
        Ok(c) => c,
        Err(_) => return repos,
    };

    let provider = match state.provider_factory.create(&credentials.kind, credentials.auth).await {
        Ok(p) => p,
        Err(_) => return repos,
    };

    let futures: Vec<_> = repos
        .iter()
        .map(|repo| {
            let provider = provider.clone();
            let owner = repo.owner.clone();
            let repo_name = repo.repo_name.clone();
            async move {
                let count = provider
                    .list_pull_requests(&owner, &repo_name)
                    .await
                    .map(|prs| prs.iter().filter(|pr| matches!(pr.state, PullRequestState::Open)).count() as i64)
                    .unwrap_or(0);
                (repo_name, count)
            }
        })
        .collect();

    let results = join_all(futures).await;

    for repo in &mut repos {
        if let Some((_, count)) = results.iter().find(|(name, _)| *name == repo.repo_name) {
            repo.open_prs_count = Some(*count);
        }
    }

    repos
}

#[tauri::command]
pub async fn list_repo_pull_requests(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
) -> Result<Vec<PullRequestDto>, String> {
    let repos = state
        .organization_repo_service
        .list_selected_repositories(&organization_id)
        .await
        .map_err(|e| e.to_string())?;

    let Some(repo) = repos.iter().find(|r| r.repo_name == repo_name) else {
        return Ok(vec![]);
    };

    let owner = repo.owner.clone();

    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(&organization_id)
    .fetch_one(&state.db_pool)
    .await
    .ok()
    .flatten();

    let Some(provider_id) = provider_id else {
        return Ok(vec![]);
    };

    let credentials = state
        .provider_service
        .credentials(&provider_id)
        .await
        .map_err(|e| e.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|e| e.to_string())?;

    let prs = provider
        .list_pull_requests(&owner, &repo_name)
        .await
        .map_err(|e| e.to_string())?;

    Ok(prs
        .into_iter()
        .filter(|pr| matches!(pr.state, PullRequestState::Open))
        .map(PullRequestDto::from)
        .collect())
}
