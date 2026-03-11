use tauri::State;
use serde::Serialize;
use crate::error::AppResult;
use crate::state::AppState;
use crate::repositories::add_local_repository::{add_local_repository as add_logic, AddLocalRepositoryResponse};
use crate::repositories::delete_local_repository::delete_local_repository as delete_logic;
use crate::threads::add_thread::add_thread as add_thread_logic;
use crate::threads::delete_thread::delete_thread as delete_thread_logic;
use crate::threads::create_thread::ThreadConfig;

#[derive(Debug, Serialize)]
pub struct ThreadRow {
    pub id: String,
    pub title: String,
    pub branch: String,
    pub status: String,
    pub created_at: String,
}

#[derive(Debug, Serialize)]
pub struct RepositoryRow {
    pub id: String,
    pub name: String,
    pub threads: Vec<ThreadRow>,
}

#[tauri::command]
pub async fn add_local_repository(
    local_path: String,
    state: State<'_, AppState>,
) -> AppResult<AddLocalRepositoryResponse> {
    add_logic(local_path, &state.db_pool).await
}

#[tauri::command]
pub async fn delete_local_repository(
    repo_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    delete_logic(repo_id, &state.db_pool).await
}

#[tauri::command]
pub async fn create_thread(
    repo_id: String,
    state: State<'_, AppState>,
) -> AppResult<ThreadConfig> {
    add_thread_logic(repo_id, &state.db_pool).await
}
#[tauri::command]
pub async fn delete_thread(
    thread_id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
    delete_thread_logic(thread_id, &state.db_pool).await
}

#[tauri::command]
pub async fn list_repositories(
    state: State<'_, AppState>,
) -> AppResult<Vec<RepositoryRow>> {
    let repos = sqlx::query_as::<_, (String, String)>(
        "SELECT id, name FROM local_repositories ORDER BY created_at DESC",
    )
    .fetch_all(&state.db_pool)
    .await?;

    let mut result = Vec::new();

    for (repo_id, repo_name) in repos {
        let threads = sqlx::query_as::<_, (String, String, String, String, String)>(
            "SELECT id, title, branch, status, created_at FROM threads WHERE repo_id = ? ORDER BY created_at ASC",
        )
        .bind(&repo_id)
        .fetch_all(&state.db_pool)
        .await?;

        let thread_rows = threads.into_iter().map(|(id, title, branch, status, created_at)| ThreadRow {
            id,
            title,
            branch,
            status,
            created_at,
        }).collect();

        result.push(RepositoryRow {
            id: repo_id,
            name: repo_name,
            threads: thread_rows,
        });
    }

    Ok(result)
}
