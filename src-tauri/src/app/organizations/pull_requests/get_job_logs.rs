use tauri::State;

use crate::state::AppState;

pub async fn get_job_logs(state: State<'_, AppState>, organization_id: String, repo_name: String, job_id: u64) -> Result<String, String> {
    let (owner, provider) = super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;
    provider
        .get_job_logs(&owner, &repo_name, job_id)
        .await
        .map_err(|e| e.to_string())
}
