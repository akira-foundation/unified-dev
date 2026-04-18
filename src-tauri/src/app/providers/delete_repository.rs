use serde::Deserialize;
use tauri::State;

use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct DeleteRepositoryInput {
    pub provider_id: String,
    pub owner: String,
    pub repo_name: String,
}

pub async fn delete_repository(
    state: State<'_, AppState>,
    input: DeleteRepositoryInput,
) -> Result<(), String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &input.provider_id)
        .await
        .map_err(|e| e.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|e| e.to_string())?;

    provider
        .delete_repository(&input.owner, &input.repo_name)
        .await
        .map_err(|e| e.to_string())
}
