use tauri::{AppHandle, State};

use crate::app::notifications;
use crate::app::notifications::prefs::NotificationPref;
use crate::app::notifications::types::Notification;
use crate::app::support::error::AppResult;
use crate::state::AppState;

#[tauri::command]
pub async fn list_notifications(
    state: State<'_, AppState>,
    limit: Option<i64>,
    only_unread: Option<bool>,
) -> AppResult<Vec<Notification>> {
    notifications::list(
        &state.db_pool,
        limit.unwrap_or(50).clamp(1, 200),
        only_unread.unwrap_or(false),
    )
    .await
}

#[tauri::command]
pub async fn unread_notifications_count(state: State<'_, AppState>) -> AppResult<i64> {
    notifications::count_unread(&state.db_pool).await
}

#[tauri::command]
pub async fn mark_notification_read(
    state: State<'_, AppState>,
    app: AppHandle,
    id: String,
) -> AppResult<()> {
    notifications::mark_read(&state.db_pool, &id).await?;
    notifications::refresh_badge(&app, &state.db_pool).await;
    Ok(())
}

#[tauri::command]
pub async fn mark_all_notifications_read(
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    notifications::mark_all_read(&state.db_pool).await?;
    notifications::refresh_badge(&app, &state.db_pool).await;
    Ok(())
}

#[tauri::command]
pub async fn delete_notification(
    state: State<'_, AppState>,
    app: AppHandle,
    id: String,
) -> AppResult<()> {
    notifications::delete(&state.db_pool, &id).await?;
    notifications::refresh_badge(&app, &state.db_pool).await;
    Ok(())
}

#[tauri::command]
pub async fn clear_notifications(state: State<'_, AppState>, app: AppHandle) -> AppResult<()> {
    notifications::clear_all(&state.db_pool).await?;
    notifications::refresh_badge(&app, &state.db_pool).await;
    Ok(())
}

#[tauri::command]
pub async fn get_notification_prefs(state: State<'_, AppState>) -> AppResult<Vec<NotificationPref>> {
    notifications::prefs::list(&state.db_pool).await
}

#[tauri::command]
pub async fn set_notification_prefs(
    state: State<'_, AppState>,
    category: String,
    in_app: bool,
    os_notify: bool,
) -> AppResult<()> {
    notifications::prefs::upsert(&state.db_pool, &category, in_app, os_notify).await
}

