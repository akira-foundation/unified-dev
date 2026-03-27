use axum::extract::{Path, State as AxumState};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;

use crate::app::threads::agents::send_message::spawn_send_message;

use super::state::RemoteHostState;
use super::support::{authorize, internal_error};
use super::types::{AcceptedResponse, RemoteSendMessageRequest};

pub async fn send_message(
    headers: HeaderMap,
    Path(thread_id): Path<String>,
    AxumState(state): AxumState<RemoteHostState>,
    Json(input): Json<RemoteSendMessageRequest>,
) -> Result<Json<AcceptedResponse>, (StatusCode, String)> {
    authorize(&headers, &state.db_pool).await?;

    spawn_send_message(
        thread_id,
        input.content,
        input.model,
        Some(false),
        input.plan_mode,
        input.thinking_budget,
        input.fast_mode,
        state.db_pool.clone(),
        state.abort_handles.clone(),
        state.app.clone(),
    )
    .await
    .map_err(internal_error)?;

    Ok(Json(AcceptedResponse { accepted: true }))
}
