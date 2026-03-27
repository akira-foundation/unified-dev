use axum::extract::{Path, State as AxumState};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;

use crate::app::chat::message::Message;

use super::state::RemoteHostState;
use super::support::{authorize, internal_error};

pub async fn get_messages(
    headers: HeaderMap,
    Path(thread_id): Path<String>,
    AxumState(state): AxumState<RemoteHostState>,
) -> Result<Json<Vec<Message>>, (StatusCode, String)> {
    authorize(&headers, &state.db_pool).await?;
    crate::app::chat::message::get_messages(&thread_id, &state.db_pool)
        .await
        .map(Json)
        .map_err(internal_error)
}
