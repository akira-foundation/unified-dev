use axum::extract::State as AxumState;
use axum::http::{HeaderMap, StatusCode};
use axum::Json;

use crate::app::threads::list_repos::{RepositoryRow, ThreadRow};

use super::state::RemoteHostState;
use super::support::{authorize, internal_error};

pub async fn list_repositories(
    headers: HeaderMap,
    AxumState(state): AxumState<RemoteHostState>,
) -> Result<Json<Vec<RepositoryRow>>, (StatusCode, String)> {
    authorize(&headers, &state.db_pool).await?;

    let repos = sqlx::query_as::<_, (String, String)>(
        "SELECT id, name FROM local_repositories ORDER BY created_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(internal_error)?;

    let mut result = Vec::new();
    for (repo_id, repo_name) in repos {
        let threads = sqlx::query_as::<_, (String, String, String, String, String, String, Option<String>, Option<i64>)>(
            "SELECT id, title, branch, workspace_path, status, created_at, pr_url, pr_is_draft FROM threads WHERE repo_id = ? ORDER BY created_at ASC",
        )
        .bind(&repo_id)
        .fetch_all(&state.db_pool)
        .await
        .map_err(internal_error)?;

        result.push(RepositoryRow {
            id: repo_id,
            name: repo_name,
            threads: threads
                .into_iter()
                .map(|(id, title, branch, workspace_path, status, created_at, pr_url, pr_is_draft)| ThreadRow {
                    id,
                    title,
                    branch,
                    workspace_path,
                    status,
                    created_at,
                    pr_url,
                    pr_is_draft: pr_is_draft.unwrap_or(0) != 0,
                })
                .collect(),
        });
    }

    Ok(Json(result))
}
