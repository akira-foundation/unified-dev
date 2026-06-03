use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct Project {
    pub id: String,
    pub name: String,
    pub provider: String,
    pub external_id: Option<String>,
    pub color: Option<String>,
    pub org_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct ProjectRepo {
    pub id: String,
    pub project_id: String,
    pub name: String,
    pub default_vcs_source_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct RepoSource {
    pub id: String,
    pub project_repo_id: String,
    pub provider: String,
    pub ref_type: String,
    #[sqlx(rename = "ref")]
    #[serde(rename = "ref")]
    pub reference: String,
    pub is_issue_source: bool,
    pub is_vcs_target: bool,
    pub created_at: String,
}

const PROJECT_COLUMNS: &str = "id, name, provider, external_id, color, org_id, created_at, updated_at";
const REPO_COLUMNS: &str = "id, project_id, name, default_vcs_source_id, created_at, updated_at";
const SOURCE_COLUMNS: &str =
    "id, project_repo_id, provider, ref_type, ref, is_issue_source, is_vcs_target, created_at";

pub async fn list(state: &AppState) -> AppResult<Vec<Project>> {
    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    let query = format!("SELECT {PROJECT_COLUMNS} FROM projects WHERE customer_id = ? ORDER BY name COLLATE NOCASE ASC");
    Ok(sqlx::query_as::<_, Project>(&query)
        .bind(customer_id)
        .fetch_all(&state.db_pool)
        .await?)
}

async fn fetch_project(state: &AppState, id: &str) -> AppResult<Project> {
    let query = format!("SELECT {PROJECT_COLUMNS} FROM projects WHERE id = ?");
    sqlx::query_as::<_, Project>(&query)
        .bind(id)
        .fetch_optional(&state.db_pool)
        .await?
        .ok_or_else(|| AppError::Provider(format!("project not found: {id}")))
}

pub async fn create(
    state: &AppState,
    name: String,
    org_id: Option<String>,
    color: Option<String>,
) -> AppResult<Project> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    sqlx::query(
        "INSERT INTO projects (id, name, provider, external_id, color, org_id, created_at, updated_at, customer_id) \
         VALUES (?, ?, 'local', NULL, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&name)
    .bind(&color)
    .bind(&org_id)
    .bind(&now)
    .bind(&now)
    .bind(&customer_id)
    .execute(&state.db_pool)
    .await?;
    fetch_project(state, &id).await
}

pub async fn update(
    state: &AppState,
    id: String,
    name: Option<String>,
    color: Option<String>,
) -> AppResult<Project> {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE projects SET name = COALESCE(?, name), color = COALESCE(?, color), updated_at = ? WHERE id = ?",
    )
    .bind(&name)
    .bind(&color)
    .bind(&now)
    .bind(&id)
    .execute(&state.db_pool)
    .await?;
    fetch_project(state, &id).await
}

pub async fn delete(state: &AppState, id: String) -> AppResult<()> {
    sqlx::query("DELETE FROM projects WHERE id = ?")
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}

pub async fn list_repos(state: &AppState) -> AppResult<Vec<ProjectRepo>> {
    let query = format!("SELECT {REPO_COLUMNS} FROM project_repos ORDER BY name COLLATE NOCASE ASC");
    Ok(sqlx::query_as::<_, ProjectRepo>(&query)
        .fetch_all(&state.db_pool)
        .await?)
}

async fn fetch_repo(state: &AppState, id: &str) -> AppResult<ProjectRepo> {
    let query = format!("SELECT {REPO_COLUMNS} FROM project_repos WHERE id = ?");
    sqlx::query_as::<_, ProjectRepo>(&query)
        .bind(id)
        .fetch_optional(&state.db_pool)
        .await?
        .ok_or_else(|| AppError::Provider(format!("repo not found: {id}")))
}

pub async fn create_repo(state: &AppState, project_id: String, name: String) -> AppResult<ProjectRepo> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO project_repos (id, project_id, name, default_vcs_source_id, created_at, updated_at) \
         VALUES (?, ?, ?, NULL, ?, ?)",
    )
    .bind(&id)
    .bind(&project_id)
    .bind(&name)
    .bind(&now)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;
    fetch_repo(state, &id).await
}

pub async fn update_repo(
    state: &AppState,
    id: String,
    name: Option<String>,
    default_vcs_source_id: Option<String>,
) -> AppResult<ProjectRepo> {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE project_repos SET name = COALESCE(?, name), default_vcs_source_id = COALESCE(?, default_vcs_source_id), updated_at = ? WHERE id = ?",
    )
    .bind(&name)
    .bind(&default_vcs_source_id)
    .bind(&now)
    .bind(&id)
    .execute(&state.db_pool)
    .await?;
    fetch_repo(state, &id).await
}

pub async fn delete_repo(state: &AppState, id: String) -> AppResult<()> {
    sqlx::query("DELETE FROM project_repos WHERE id = ?")
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}

pub async fn list_sources(state: &AppState) -> AppResult<Vec<RepoSource>> {
    let query = format!("SELECT {SOURCE_COLUMNS} FROM repo_sources");
    Ok(sqlx::query_as::<_, RepoSource>(&query)
        .fetch_all(&state.db_pool)
        .await?)
}

pub async fn add_source(
    state: &AppState,
    project_repo_id: String,
    provider: String,
    ref_type: String,
    reference: String,
    is_issue_source: bool,
    is_vcs_target: bool,
) -> AppResult<RepoSource> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO repo_sources (id, project_repo_id, provider, ref_type, ref, is_issue_source, is_vcs_target, created_at) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?) \
         ON CONFLICT(provider, ref_type, ref) DO UPDATE SET project_repo_id = excluded.project_repo_id, is_issue_source = excluded.is_issue_source, is_vcs_target = excluded.is_vcs_target",
    )
    .bind(&id)
    .bind(&project_repo_id)
    .bind(&provider)
    .bind(&ref_type)
    .bind(&reference)
    .bind(is_issue_source)
    .bind(is_vcs_target)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;

    let query = format!(
        "SELECT {SOURCE_COLUMNS} FROM repo_sources WHERE provider = ? AND ref_type = ? AND ref = ?"
    );
    sqlx::query_as::<_, RepoSource>(&query)
        .bind(&provider)
        .bind(&ref_type)
        .bind(&reference)
        .fetch_optional(&state.db_pool)
        .await?
        .ok_or_else(|| AppError::Provider("failed to persist repo source".into()))
}

pub async fn remove_source(state: &AppState, id: String) -> AppResult<()> {
    sqlx::query("DELETE FROM repo_sources WHERE id = ?")
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}
