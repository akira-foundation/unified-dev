use tauri::State;

use crate::db::models::{CreateProviderInput, ProviderSummary};
use crate::state::AppState;

#[tauri::command]
pub async fn create_provider(
    state: State<'_, AppState>,
    input: CreateProviderInput,
) -> Result<ProviderSummary, String> {
    state
        .provider_service
        .create_provider(input)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn list_providers(state: State<'_, AppState>) -> Result<Vec<ProviderSummary>, String> {
    state
        .provider_service
        .list_providers()
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn delete_provider(state: State<'_, AppState>, provider_id: String) -> Result<(), String> {
    state
        .provider_service
        .delete_provider(&provider_id)
        .await
        .map_err(|error| error.to_string())
}
