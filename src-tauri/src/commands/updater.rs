use serde::Serialize;
use tauri::{AppHandle, Manager};
use tauri_plugin_updater::UpdaterExt;

use crate::app::settings::update as update_settings;
use crate::database::database_path;
use crate::state::AppState;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateInfo {
    pub version: String,
    pub current_version: String,
    pub body: Option<String>,
}

#[tauri::command]
pub async fn check_for_updates(app: AppHandle) -> Result<Option<UpdateInfo>, String> {
    let updater = app.updater().map_err(|e| e.to_string())?;

    let update = updater.check().await.map_err(|e| e.to_string())?;

    Ok(update.map(|u| UpdateInfo {
        version: u.version.clone(),
        current_version: u.current_version.clone(),
        body: u.body.clone(),
    }))
}

#[tauri::command]
pub async fn install_update(app: AppHandle) -> Result<(), String> {
    let updater = app.updater().map_err(|e| e.to_string())?;

    let update = updater.check().await.map_err(|e| e.to_string())?;

    if let Some(update) = update {
        if let Some(state) = app.try_state::<AppState>() {
            let db_path = database_path(&app).map_err(|e| e.to_string())?;
            let _ = update_settings::perform_backup(
                &state.pool().await.map_err(|e| e.to_string())?,
                &db_path,
                &update.version,
            )
            .await
            .map_err(|e| format!("backup failed: {e}"));
        }

        update
            .download_and_install(|_, _| {}, || {})
            .await
            .map_err(|e| e.to_string())?;

        app.restart();
    }

    Ok(())
}
