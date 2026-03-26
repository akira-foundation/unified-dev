use tauri::State;

use crate::database::models::ProviderSummary;
use crate::state::AppState;

pub async fn list(state: State<'_, AppState>) -> Result<Vec<ProviderSummary>, String> {
    state.provider_repo.list().await.map_err(|error| error.to_string())
}
