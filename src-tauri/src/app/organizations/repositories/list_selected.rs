use tauri::State;

use crate::db::models::OrganizationRepoSummary;
use crate::state::AppState;

pub async fn list_selected_repositories(state: State<'_, AppState>, organization_id: String) -> Result<Vec<OrganizationRepoSummary>, String> {
    state
        .organization_repos
        .list_selected_by_org(&organization_id)
        .await
        .map_err(|error| error.to_string())
}
