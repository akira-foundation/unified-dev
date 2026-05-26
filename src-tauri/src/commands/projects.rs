use tauri::State;

use crate::app::projects::{self, Project, ProjectSource};
use crate::state::AppState;

#[tauri::command]
pub async fn project_list(state: State<'_, AppState>) -> Result<Vec<Project>, String> {
    projects::list(&state).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_list_sources(
    state: State<'_, AppState>,
) -> Result<Vec<ProjectSource>, String> {
    projects::list_sources(&state)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_create(
    state: State<'_, AppState>,
    name: String,
    color: Option<String>,
) -> Result<Project, String> {
    projects::create(&state, name, color)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_update(
    state: State<'_, AppState>,
    id: String,
    name: Option<String>,
    color: Option<String>,
) -> Result<Project, String> {
    projects::update(&state, id, name, color)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_delete(state: State<'_, AppState>, id: String) -> Result<(), String> {
    projects::delete(&state, id).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_add_source(
    state: State<'_, AppState>,
    project_id: String,
    provider: String,
    ref_type: String,
    reference: String,
) -> Result<ProjectSource, String> {
    projects::add_source(&state, project_id, provider, ref_type, reference)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_remove_source(
    state: State<'_, AppState>,
    id: String,
) -> Result<(), String> {
    projects::remove_source(&state, id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_import(
    state: State<'_, AppState>,
    provider: String,
) -> Result<Vec<Project>, String> {
    projects::import_from_provider(&state, provider)
        .await
        .map_err(|e| e.to_string())
}
