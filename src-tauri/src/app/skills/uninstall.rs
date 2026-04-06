use tauri::{AppHandle, Manager, State};

use crate::state::AppState;
use crate::app::support::error::AppResult;

pub async fn uninstall(id: String, app_handle: AppHandle, state: State<'_, AppState>) -> AppResult<()> {
    if let Ok(app_data) = app_handle.path().app_data_dir() {
        let skill_dir = app_data.join("skills").join(&id);
        if skill_dir.is_dir() {
            let _ = std::fs::remove_dir_all(&skill_dir);
        }

        let icons_dir = app_data.join("skills").join(".icons");
        for ext in &["png", "jpg", "jpeg", "webp", "svg"] {
            let icon = icons_dir.join(format!("{}.{}", id, ext));
            if icon.exists() {
                let _ = std::fs::remove_file(icon);
            }
        }
    }

    sqlx::query("DELETE FROM skills WHERE id = ?")
        .bind(&id)
        .execute(&state.db_pool)
        .await?;

    Ok(())
}
