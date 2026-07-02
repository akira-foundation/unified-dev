use tauri::{AppHandle, Manager, State};

use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn set_icon(
    id: String,
    data: Vec<u8>,
    extension: String,
    app_handle: AppHandle,
    state: State<'_, AppState>,
) -> AppResult<String> {
    let icons = app_handle
        .path()
        .app_data_dir()
        .map(|d| d.join("skills").join(".icons"))
        .map_err(|_| {
            crate::app::support::error::AppError::Internal("Cannot resolve app data dir".into())
        })?;

    std::fs::create_dir_all(&icons)?;

    let filename = format!("{}.{}", id, extension);
    let dest = icons.join(&filename);
    std::fs::write(&dest, &data)?;

    let path_str = dest.to_string_lossy().to_string();
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    sqlx::query("UPDATE skills SET icon_path = ? WHERE id = ? AND customer_id IS ?")
        .bind(&path_str)
        .bind(&id)
        .bind(&customer_id)
        .execute(&state.pool().await?)
        .await?;

    Ok(path_str)
}
