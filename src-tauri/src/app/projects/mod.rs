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
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
#[serde(rename_all = "camelCase")]
pub struct ProjectSource {
    pub id: String,
    pub project_id: String,
    pub provider: String,
    pub ref_type: String,
    #[sqlx(rename = "ref")]
    #[serde(rename = "ref")]
    pub reference: String,
    pub created_at: String,
}

const PROJECT_COLUMNS: &str = "id, name, provider, external_id, color, created_at, updated_at";
const SOURCE_COLUMNS: &str = "id, project_id, provider, ref_type, ref, created_at";

pub async fn list(state: &AppState) -> AppResult<Vec<Project>> {
    let query = format!("SELECT {PROJECT_COLUMNS} FROM projects ORDER BY name COLLATE NOCASE ASC");
    Ok(sqlx::query_as::<_, Project>(&query)
        .fetch_all(&state.db_pool)
        .await?)
}

pub async fn list_sources(state: &AppState) -> AppResult<Vec<ProjectSource>> {
    let query = format!("SELECT {SOURCE_COLUMNS} FROM project_sources");
    Ok(sqlx::query_as::<_, ProjectSource>(&query)
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

pub async fn create(state: &AppState, name: String, color: Option<String>) -> AppResult<Project> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO projects (id, name, provider, external_id, color, created_at, updated_at) \
         VALUES (?, ?, 'local', NULL, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&name)
    .bind(&color)
    .bind(&now)
    .bind(&now)
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
        "UPDATE projects SET \
         name = COALESCE(?, name), \
         color = COALESCE(?, color), \
         updated_at = ? \
         WHERE id = ?",
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

pub async fn add_source(
    state: &AppState,
    project_id: String,
    provider: String,
    ref_type: String,
    reference: String,
) -> AppResult<ProjectSource> {
    let id = Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO project_sources (id, project_id, provider, ref_type, ref, created_at) \
         VALUES (?, ?, ?, ?, ?, ?) \
         ON CONFLICT(provider, ref_type, ref) DO UPDATE SET project_id = excluded.project_id",
    )
    .bind(&id)
    .bind(&project_id)
    .bind(&provider)
    .bind(&ref_type)
    .bind(&reference)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;

    let query = format!(
        "SELECT {SOURCE_COLUMNS} FROM project_sources WHERE provider = ? AND ref_type = ? AND ref = ?"
    );
    sqlx::query_as::<_, ProjectSource>(&query)
        .bind(&provider)
        .bind(&ref_type)
        .bind(&reference)
        .fetch_optional(&state.db_pool)
        .await?
        .ok_or_else(|| AppError::Provider("failed to persist project source".into()))
}

pub async fn remove_source(state: &AppState, id: String) -> AppResult<()> {
    sqlx::query("DELETE FROM project_sources WHERE id = ?")
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}

pub async fn import_from_provider(state: &AppState, provider: String) -> AppResult<Vec<Project>> {
    let named = crate::app::tracker::list_projects_named(state, &provider).await?;
    let now = chrono::Utc::now().to_rfc3339();
    let mut ids: Vec<String> = Vec::with_capacity(named.len());

    for entry in &named {
        let id = Uuid::new_v4().to_string();
        sqlx::query(
            "INSERT INTO projects (id, name, provider, external_id, color, created_at, updated_at) \
             VALUES (?, ?, ?, ?, NULL, ?, ?) \
             ON CONFLICT(provider, external_id) DO UPDATE SET name = excluded.name, updated_at = excluded.updated_at",
        )
        .bind(&id)
        .bind(&entry.name)
        .bind(&provider)
        .bind(&entry.id)
        .bind(&now)
        .bind(&now)
        .execute(&state.db_pool)
        .await?;

        let resolved_id: String = sqlx::query_scalar(
            "SELECT id FROM projects WHERE provider = ? AND external_id = ?",
        )
        .bind(&provider)
        .bind(&entry.id)
        .fetch_one(&state.db_pool)
        .await?;

        add_source(
            state,
            resolved_id.clone(),
            provider.clone(),
            "project".to_string(),
            entry.id.clone(),
        )
        .await?;

        ids.push(resolved_id);
    }

    let mut projects = Vec::with_capacity(ids.len());
    for id in ids {
        projects.push(fetch_project(state, &id).await?);
    }
    Ok(projects)
}
