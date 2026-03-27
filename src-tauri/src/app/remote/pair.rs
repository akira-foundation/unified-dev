use axum::extract::State as AxumState;
use axum::http::StatusCode;
use axum::Json;
use tauri::Manager;

use super::state::RemoteHostState;
use super::support::{internal_error, random_token};
use super::types::{PairRequest, PairResponse};

pub async fn pair(
    AxumState(state): AxumState<RemoteHostState>,
    Json(input): Json<PairRequest>,
) -> Result<Json<PairResponse>, (StatusCode, String)> {
    let settings = crate::app::settings::remote::get(state.app.state::<crate::state::AppState>())
        .await
        .map_err(|error| (StatusCode::INTERNAL_SERVER_ERROR, error.to_string()))?;

    if input.pairing_code.trim() != settings.pairing_code.trim() {
        return Err((StatusCode::UNAUTHORIZED, "Invalid pairing code".to_string()));
    }

    let token = random_token();
    let device_id = uuid::Uuid::new_v4().to_string().to_uppercase();
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO remote_devices (id, name, token_hash, fingerprint, user_agent, last_seen_at, revoked_at, created_at) VALUES (?, ?, ?, ?, ?, ?, NULL, ?)",
    )
    .bind(&device_id)
    .bind(&input.device_name)
    .bind(&token)
    .bind(&input.device_fingerprint)
    .bind("remote-web")
    .bind(&now)
    .bind(&now)
    .execute(&state.db_pool)
    .await
    .map_err(internal_error)?;

    Ok(Json(PairResponse {
        access_token: token,
        device_id,
        host_name: settings.host_name,
        host_fingerprint: settings.host_fingerprint,
    }))
}
