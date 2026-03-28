use tauri::State;

use crate::database::records::OrganizationRepoWithOrg;
use crate::state::AppState;

pub async fn list_all(state: State<'_, AppState>) -> Result<Vec<OrganizationRepoWithOrg>, String> {
    sqlx::query_as::<_, OrganizationRepoWithOrg>(
        "SELECT o_r.id, o_r.organization_id, org.name as organization_name, o_r.owner, o_r.repo_name, o_r.visibility, o_r.is_selected, o_r.auto_sync, o_r.default_branch, o_r.open_prs_count, o_r.created_at FROM organization_repos o_r JOIN organizations org ON org.id = o_r.organization_id JOIN providers p ON p.id = org.provider_id WHERE o_r.is_selected = 1 ORDER BY org.name, o_r.repo_name",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}
