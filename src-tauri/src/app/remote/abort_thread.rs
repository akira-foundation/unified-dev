use axum::extract::{Path, State as AxumState};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;

use crate::app::threads::agents::abort_agent::abort_agent_core;

use super::state::RemoteHostState;
use super::support::{authorize, internal_error};
use super::types::AcceptedResponse;

pub async fn abort_thread(
    headers: HeaderMap,
    Path(thread_id): Path<String>,
    AxumState(state): AxumState<RemoteHostState>,
) -> Result<Json<AcceptedResponse>, (StatusCode, String)> {
    authorize(&headers, &state.db_pool).await?;
    abort_agent_core(thread_id, state.abort_handles.clone(), state.app.clone())
        .await
        .map_err(internal_error)?;
    Ok(Json(AcceptedResponse { accepted: true }))
}
