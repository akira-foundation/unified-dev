use tauri::State;

use crate::app::providers::request::UpdateProviderAuthRequest;
use crate::state::AppState;

pub async fn update_auth(state: State<'_, AppState>, input: UpdateProviderAuthRequest) -> Result<(), String> {
    let (auth_type, auth_payload) = crate::app::providers::credentials::serialize_auth(&state, &input.auth)
        .map_err(|error| error.to_string())?;
    state
        .provider_repo
        .update_auth(&input.provider_id, &auth_type, &auth_payload)
        .await
        .map_err(|error| error.to_string())
}
