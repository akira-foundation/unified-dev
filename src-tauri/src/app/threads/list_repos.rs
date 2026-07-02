use serde::Serialize;

use crate::app::support::error::AppResult;
use crate::state::AppState;

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
    pub default_branch: String,
    pub display_name: Option<String>,
    pub default_model_id: Option<String>,
    pub review_model_id: Option<String>,
    pub default_merge_action: Option<String>,
    pub remote_url: Option<String>,
    pub threads: Vec<ThreadRow>,
}

pub async fn list(state: tauri::State<'_, AppState>) -> AppResult<Vec<RepositoryRow>> {
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    let repos = sqlx::query_as::<_, (String, String, String, Option<String>, Option<String>, Option<String>, Option<String>, Option<String>)>(
        "SELECT id, name, default_branch, display_name, default_model_id, review_model_id, default_merge_action, remote_url FROM local_repositories WHERE customer_id = ? ORDER BY created_at DESC",
    )
    .bind(&customer_id)
    .fetch_all(&state.pool().await?)
    .await?;

    let mut result = Vec::new();

    for (
        repo_id,
        repo_name,
        default_branch,
        display_name,
        default_model_id,
        review_model_id,
        default_merge_action,
        remote_url,
    ) in repos
    {
        let threads = sqlx::query_as::<_, (String, String, String, String, String, String, Option<String>, Option<i64>)>(
            "SELECT id, title, branch, workspace_path, status, created_at, pr_url, pr_is_draft FROM threads WHERE repo_id = ? ORDER BY created_at ASC",
        )
        .bind(&repo_id)
        .fetch_all(&state.pool().await?)
        .await?;

        let thread_rows = threads
            .into_iter()
            .map(
                |(id, title, branch, workspace_path, status, created_at, pr_url, pr_is_draft)| {
                    ThreadRow {
                        id,
                        title,
                        branch,
                        workspace_path,
                        status,
                        created_at,
                        pr_url,
                        pr_is_draft: pr_is_draft.unwrap_or(0) != 0,
                    }
                },
            )
            .collect();

        result.push(RepositoryRow {
            id: repo_id,
            name: repo_name,
            default_branch,
            display_name,
            default_model_id,
            review_model_id,
            default_merge_action,
            remote_url,
            threads: thread_rows,
        });
    }

    Ok(result)
}
