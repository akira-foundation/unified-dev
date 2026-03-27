use axum::extract::{Path, State as AxumState};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;

use crate::app::repos::types::FileChange;

use super::state::RemoteHostState;
use super::support::{authorize, internal_error, thread_workspace_path};

pub async fn get_changes(
    headers: HeaderMap,
    Path(thread_id): Path<String>,
    AxumState(state): AxumState<RemoteHostState>,
) -> Result<Json<Vec<FileChange>>, (StatusCode, String)> {
    authorize(&headers, &state.db_pool).await?;
    let workspace_path = thread_workspace_path(&state.db_pool, &thread_id).await?;
    crate::app::repos::changes(workspace_path)
        .await
        .map(Json)
        .map_err(internal_error)
}
