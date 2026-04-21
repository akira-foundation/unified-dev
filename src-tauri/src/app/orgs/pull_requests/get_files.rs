use tauri::State;

use crate::providers::dto::PrFileDto;
use crate::state::AppState;

pub async fn get_files(state: State<'_, AppState>, organization_id: String, repo_name: String, pr_number: u64) -> Result<Vec<PrFileDto>, String> {
    let (owner, repo_name, provider, _) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    let files = provider
        .list_pull_request_files(&owner, &repo_name, pr_number)
        .await
        .map_err(|e| e.to_string())?;
    Ok(files.into_iter().map(PrFileDto::from).collect())
}
