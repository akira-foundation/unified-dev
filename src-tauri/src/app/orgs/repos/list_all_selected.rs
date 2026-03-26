use tauri::State;

use crate::database::models::OrganizationRepoWithOrg;
use crate::state::AppState;

pub async fn list_all(state: State<'_, AppState>) -> Result<Vec<OrganizationRepoWithOrg>, String> {
    state
        .organization_repos
        .list_all_selected()
        .await
        .map_err(|error| error.to_string())
}
