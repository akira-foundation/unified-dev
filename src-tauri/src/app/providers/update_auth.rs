use tauri::State;

use crate::app::providers::request::UpdateProviderAuthRequest;
use crate::state::AppState;

pub async fn update_auth(
    state: State<'_, AppState>,
    input: UpdateProviderAuthRequest,
) -> Result<(), String> {
    let (auth_type, auth_payload) =
        crate::app::providers::credentials::serialize_auth(&state, &input.auth)
            .map_err(|e| e.to_string())?;

    sqlx::query("UPDATE providers SET auth_type = ?, auth_payload = ? WHERE id = ?")
        .bind(&auth_type)
        .bind(&auth_payload)
        .bind(&input.provider_id)
        .execute(&state.pool().await.map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}
