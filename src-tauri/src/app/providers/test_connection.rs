use tauri::State;

use crate::db::inputs::TestProviderInput;
use crate::providers::types::ProviderKind;
use crate::state::AppState;

pub async fn test_connection(state: State<'_, AppState>, input: TestProviderInput) -> Result<(), String> {
    let kind = ProviderKind::from_str(&input.kind);
    let provider = state
        .provider_factory
        .create(&kind, input.auth)
        .await
        .map_err(|error| error.to_string())?;

    provider
        .validate_auth()
        .await
        .map_err(|error| error.to_string())
}
