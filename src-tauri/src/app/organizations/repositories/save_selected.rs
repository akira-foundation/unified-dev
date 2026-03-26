use tauri::State;

use crate::db::inputs::SelectedRepositoryInput;
use crate::providers::types::PullRequestState;
use crate::state::AppState;

pub async fn save_selected(state: State<'_, AppState>, organization_id: String, repo_list: Vec<SelectedRepositoryInput>) -> Result<(), String> {
    let provider = match crate::app::organizations::resolve_provider::resolve_provider_for_org(&state, &organization_id).await {
        Ok(p) => p,
        Err(_) => {
            let created_at = time::OffsetDateTime::now_utc()
                .format(&time::format_description::well_known::Rfc3339)
                .unwrap_or_default();

            return state
                .organization_repos
                .replace_selected_repos(&organization_id, &repo_list, &created_at)
                .await
                .map_err(|error| error.to_string());
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

    let results = futures_util::future::join_all(futures).await;
    let mut enriched = repo_list;

    for repo in &mut enriched {
        if let Some((_, count)) = results.iter().find(|(name, _)| *name == repo.repo_name) {
            repo.open_prs_count = Some(*count);
        }
    }

    let created_at = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_default();

    state
        .organization_repos
        .replace_selected_repos(&organization_id, &enriched, &created_at)
        .await
        .map_err(|error| error.to_string())
}
