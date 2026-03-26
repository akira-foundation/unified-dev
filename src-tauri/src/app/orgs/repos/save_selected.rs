use tauri::State;

use crate::app::orgs::request::SelectRepoRequest;
use crate::providers::enums::PullRequestState;
use crate::state::AppState;

pub async fn save_selected(state: State<'_, AppState>, organization_id: String, repo_list: Vec<SelectRepoRequest>) -> Result<(), String> {
    let provider = match crate::app::orgs::resolve_provider::resolve_provider_for_org(&state, &organization_id).await {
        Ok(p) => p,
        Err(_) => {
            let created_at = time::OffsetDateTime::now_utc()
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default();

            return replace_selected_repos(&state, &organization_id, &repo_list, &created_at).await;
        }
    };

    let futures: Vec<_> = repo_list
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

    let results: Vec<(String, i64)> = futures_util::future::join_all(futures).await;
    let mut enriched = repo_list;

    for repo in &mut enriched {
        if let Some((_, count)) = results.iter().find(|(name, _)| *name == repo.repo_name) {
            repo.open_prs_count = Some(*count);
        }
    }

    let created_at = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_default();

    replace_selected_repos(&state, &organization_id, &enriched, &created_at).await
}

async fn replace_selected_repos(state: &AppState, organization_id: &str, repos: &[SelectRepoRequest], created_at: &str) -> Result<(), String> {
    let mut transaction = state.db_pool.begin().await.map_err(|e| e.to_string())?;

    for repo in repos {
        let updated = sqlx::query(
            "UPDATE organization_repos SET visibility = ?, is_selected = ?, auto_sync = ?, default_branch = ? WHERE organization_id = ? AND repo_name = ?",
        )
        .bind(&repo.visibility)
        .bind(repo.is_selected)
        .bind(repo.auto_sync.unwrap_or(true))
        .bind(repo.default_branch.as_deref().unwrap_or("main"))
        .bind(organization_id)
        .bind(&repo.repo_name)
        .execute(&mut *transaction)
        .await
        .map_err(|e| e.to_string())?;

        if updated.rows_affected() == 0 {
            sqlx::query(
                "INSERT INTO organization_repos (organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            )
            .bind(organization_id)
            .bind(&repo.owner)
            .bind(&repo.repo_name)
            .bind(&repo.visibility)
            .bind(repo.is_selected)
            .bind(repo.auto_sync.unwrap_or(true))
            .bind(repo.default_branch.as_deref().unwrap_or("main"))
            .bind(repo.open_prs_count.unwrap_or(0))
            .bind(created_at)
            .execute(&mut *transaction)
            .await
            .map_err(|e| e.to_string())?;
        }
    }

    transaction.commit().await.map_err(|e| e.to_string())
}
