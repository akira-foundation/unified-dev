use tauri::State;
use std::path::PathBuf;

use crate::state::AppState;
use crate::support::error::AppResult;

fn icons_dir() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join(".agents").join("skills").join(".icons"))
}

pub async fn set_skill_icon(id: String, data: Vec<u8>, extension: String, state: State<'_, AppState>) -> AppResult<String> {
    let icons = match icons_dir() {
        Some(d) => d,
        None => return Err(crate::support::error::AppError::Internal("Cannot resolve home dir".into())),
    };
    std::fs::create_dir_all(&icons)?;

    let filename = format!("{}.{}", id, extension);
    let dest = icons.join(&filename);
    std::fs::write(&dest, &data)?;

    let path_str = dest.to_string_lossy().to_string();
    sqlx::query("UPDATE skills SET icon_path = ? WHERE id = ?")
        .bind(&path_str)
        .bind(&id)
        .execute(&state.db_pool)
        .await?;

    Ok(path_str)
}
