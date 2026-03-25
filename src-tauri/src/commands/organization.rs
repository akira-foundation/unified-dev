use std::sync::Arc;

use futures_util::future::join_all;
use tauri::State;

use crate::db::models::{
    CreateOrganizationInput, OrganizationRepoSummary, OrganizationRepoWithOrg, OrganizationSummary, SelectedRepositoryInput,
    UpdateOrganizationInput,
};
use crate::core::provider::types::{BranchDto, CiCheckDto, PrCommentDto, PrFileDto, PrMergeStrategy, PrReviewEvent, PullRequestDto, PullRequestState};
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

async fn resolve_pr_provider(
    state: &crate::state::AppState,
    organization_id: &str,
    repo_name: &str,
) -> Result<(String, Arc<dyn crate::core::provider::traits::VcsProvider>), String> {
    let repos = state
        .organization_repo_service
        .list_selected_repositories(organization_id)
        .await
        .map_err(|e| e.to_string())?;

    let repo = repos
        .iter()
        .find(|r| r.repo_name == repo_name)
        .ok_or_else(|| format!("repository '{}' not found", repo_name))?;

    let owner = repo.owner.clone();

    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(organization_id)
    .fetch_one(&state.db_pool)
    .await
    .ok()
    .flatten()
    .ok_or_else(|| "no provider linked to organization".to_string())?;

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

    Ok((owner, provider))
}

#[tauri::command]
pub async fn get_pr_comments(
    state: State<'_, crate::state::AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
) -> Result<Vec<PrCommentDto>, String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let comments = provider
        .get_pull_request_comments(&owner, &repo_name, pr_number)
        .await
        .map_err(|e| e.to_string())?;
    Ok(comments.into_iter().map(PrCommentDto::from).collect())
}

#[tauri::command]
pub async fn post_pr_comment(
    state: State<'_, crate::state::AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
    body: String,
) -> Result<PrCommentDto, String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let comment = provider
        .post_pull_request_comment(&owner, &repo_name, pr_number, &body)
        .await
        .map_err(|e| e.to_string())?;
    Ok(PrCommentDto::from(comment))
}

#[tauri::command]
pub async fn submit_pr_review(
    state: State<'_, crate::state::AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
    event: PrReviewEvent,
    body: Option<String>,
) -> Result<(), String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .submit_pull_request_review(&owner, &repo_name, pr_number, event, body.as_deref())
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn merge_pr(
    state: State<'_, crate::state::AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
    strategy: PrMergeStrategy,
) -> Result<(), String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .merge_pull_request(&owner, &repo_name, pr_number, strategy)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn get_pr_files(
    state: State<'_, crate::state::AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
) -> Result<Vec<PrFileDto>, String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let files = provider
        .list_pull_request_files(&owner, &repo_name, pr_number)
        .await
        .map_err(|e| e.to_string())?;
    Ok(files.into_iter().map(PrFileDto::from).collect())
}

#[tauri::command]
pub async fn get_pr_checks(
    state: State<'_, crate::state::AppState>,
    organization_id: String,
    repo_name: String,
    head_sha: String,
) -> Result<Vec<CiCheckDto>, String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let checks = provider
        .list_pr_checks(&owner, &repo_name, &head_sha)
        .await
        .map_err(|e| e.to_string())?;
    Ok(checks.into_iter().map(CiCheckDto::from).collect())
}

#[tauri::command]
pub async fn get_job_logs(
    state: State<'_, crate::state::AppState>,
    organization_id: String,
    repo_name: String,
    job_id: u64,
) -> Result<String, String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .get_job_logs(&owner, &repo_name, job_id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn list_repo_branches(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
) -> Result<Vec<BranchDto>, String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let branches = provider
        .list_branches(&owner, &repo_name)
        .await
        .map_err(|e| e.to_string())?;
    Ok(branches.into_iter().map(BranchDto::from).collect())
}

#[tauri::command]
pub async fn create_repo_branch(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    branch_name: String,
    from_sha: String,
) -> Result<BranchDto, String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let branch = provider
        .create_branch(&owner, &repo_name, &branch_name, &from_sha)
        .await
        .map_err(|e| e.to_string())?;
    Ok(BranchDto::from(branch))
}

#[tauri::command]
pub async fn delete_repo_branch(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    branch_name: String,
) -> Result<(), String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .delete_branch(&owner, &repo_name, &branch_name)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn sync_pull_requests(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    _owner: Option<String>,
) -> Result<Vec<PullRequestDto>, String> {
    let (owner, provider) = resolve_pr_provider(&state, &organization_id, &repo_name).await?;
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
