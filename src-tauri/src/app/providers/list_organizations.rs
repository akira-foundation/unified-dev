use tauri::State;

use crate::providers::types::ProviderOrg;
use crate::state::AppState;

pub async fn list_organizations(state: State<'_, AppState>, provider_id: String) -> Result<Vec<ProviderOrg>, String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &provider_id)
        .await
        .map_err(|error| error.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|error| error.to_string())?;

    provider
        .list_organizations()
        .await
        .map_err(|error| error.to_string())
}
