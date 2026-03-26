use serde::Serialize;

use crate::state::AppState;
use crate::app::support::error::AppResult;

#[derive(Debug, Serialize)]
pub struct ThreadRow {
    pub id: String,
    pub title: String,
    pub branch: String,
    pub workspace_path: String,
    pub status: String,
    pub created_at: String,
    pub pr_url: Option<String>,
    pub pr_is_draft: bool,
}

#[derive(Debug, Serialize)]
pub struct RepositoryRow {
    pub id: String,
    pub name: String,
    pub threads: Vec<ThreadRow>,
}

pub async fn list(state: tauri::State<'_, AppState>) -> AppResult<Vec<RepositoryRow>> {
    let repos = sqlx::query_as::<_, (String, String)>(
        "SELECT id, name FROM local_repositories ORDER BY created_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await?;

    let mut result = Vec::new();

    for (repo_id, repo_name) in repos {
        let threads = sqlx::query_as::<_, (String, String, String, String, String, String, Option<String>, Option<i64>)>(
            "SELECT id, title, branch, workspace_path, status, created_at, pr_url, pr_is_draft FROM threads WHERE repo_id = ? ORDER BY created_at ASC",
        )
        .bind(&repo_id)
        .fetch_all(&state.db_pool)
        .await?;

        let thread_rows = threads
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
            .collect();

        result.push(RepositoryRow {
            id: repo_id,
            name: repo_name,
            threads: thread_rows,
        });
    }

    Ok(result)
}
