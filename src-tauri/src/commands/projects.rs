use tauri::State;

use crate::app::projects::{self, Project, ProjectRepo, RepoSource};
use crate::state::AppState;

#[tauri::command]
pub async fn project_list(state: State<'_, AppState>) -> Result<Vec<Project>, String> {
    projects::list(&state).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_create(
    state: State<'_, AppState>,
    name: String,
    org_id: Option<String>,
    color: Option<String>,
) -> Result<Project, String> {
    projects::create(&state, name, org_id, color)
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
pub async fn project_repo_list(state: State<'_, AppState>) -> Result<Vec<ProjectRepo>, String> {
    projects::list_repos(&state).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_repo_create(
    state: State<'_, AppState>,
    project_id: String,
    name: String,
) -> Result<ProjectRepo, String> {
    projects::create_repo(&state, project_id, name)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_repo_update(
    state: State<'_, AppState>,
    id: String,
    name: Option<String>,
    default_vcs_source_id: Option<String>,
) -> Result<ProjectRepo, String> {
    projects::update_repo(&state, id, name, default_vcs_source_id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn project_repo_delete(state: State<'_, AppState>, id: String) -> Result<(), String> {
    projects::delete_repo(&state, id)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn repo_source_list(state: State<'_, AppState>) -> Result<Vec<RepoSource>, String> {
    projects::list_sources(&state)
        .await
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn repo_source_add(
    state: State<'_, AppState>,
    app: tauri::AppHandle,
    project_repo_id: String,
    provider: String,
    ref_type: String,
    reference: String,
    is_issue_source: bool,
    is_vcs_target: bool,
) -> Result<RepoSource, String> {
    let source = projects::add_source(
        &state,
        project_repo_id,
        provider.clone(),
        ref_type,
        reference,
        is_issue_source,
        is_vcs_target,
    )
    .await
    .map_err(|e| e.to_string())?;

    if is_issue_source {
        let handle = app.clone();
        let provider = provider.clone();
        tauri::async_runtime::spawn(async move {
            let state = tauri::Manager::state::<AppState>(&handle);
            let _ = crate::app::tracker::sync(&state, provider, Default::default()).await;
            let _ = tauri::Emitter::emit(
                &handle,
                "sync:completed",
                serde_json::json!({ "kind": "issues", "orgId": "" }),
            );
        });
    }

    Ok(source)
}

#[tauri::command]
pub async fn repo_source_remove(state: State<'_, AppState>, id: String) -> Result<(), String> {
    projects::remove_source(&state, id)
        .await
        .map_err(|e| e.to_string())
}
