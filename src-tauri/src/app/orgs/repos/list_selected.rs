use tauri::State;

use crate::database::records::OrganizationRepoSummary;
use crate::state::AppState;

pub async fn list_selected(
    state: State<'_, AppState>,
    organization_id: String,
) -> Result<Vec<OrganizationRepoSummary>, String> {
    sqlx::query_as::<_, OrganizationRepoSummary>(
        "SELECT id, organization_id, owner, repo_name, visibility, is_selected, auto_sync, default_branch, open_prs_count, is_fork, fork_owner, fork_repo, created_at FROM organization_repos WHERE organization_id = ? AND is_selected = 1 ORDER BY repo_name",
    )
    .bind(&organization_id)
    .fetch_all(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())
}
