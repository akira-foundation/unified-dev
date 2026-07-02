use sqlx::SqlitePool;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_notification::NotificationExt;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::app::support::error::AppResult;

use super::prefs;
use super::types::{Notification, NotificationInput};

pub async fn refresh_badge(app: &AppHandle, pool: &SqlitePool) {
    if let Ok(count) = count_unread(pool).await {
        if let Some(window) = app.get_webview_window("main") {
            let value = if count > 0 { Some(count) } else { None };
            let _ = window.set_badge_count(value);
        }
    }
}

const DEFAULT_TTL_DAYS: i64 = 30;
const MAX_ITEMS: i64 = 500;

pub async fn notify(app: &AppHandle, input: NotificationInput) -> AppResult<Option<Notification>> {
    let pool = {
        let state = app.state::<crate::state::AppState>();
        state.pool().await?
    };

    let category = input.category.as_str();
    let severity = input.severity.as_str();
    let (in_app, os_notify) = prefs::resolve(&pool, category).await;

    if !in_app && !os_notify {
        return Ok(None);
    }

    let id = Uuid::new_v4().to_string();
    let now = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_default();
    let ttl_days = input.ttl_days.unwrap_or(DEFAULT_TTL_DAYS);
    let expires_at = OffsetDateTime::now_utc()
        .checked_add(time::Duration::days(ttl_days))
        .and_then(|dt| dt.format(&Rfc3339).ok());

    let inserted = if in_app {
        sqlx::query(
            "INSERT INTO notifications (id, category, severity, title, body, action_type, action_payload, read_at, created_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)",
        )
        .bind(&id)
        .bind(category)
        .bind(severity)
        .bind(&input.title)
        .bind(&input.body)
        .bind(&input.action_type)
        .bind(&input.action_payload)
        .bind(&now)
        .bind(&expires_at)
        .execute(&pool)
        .await?;
        true
    } else {
        false
    };

    if os_notify {
        let mut builder = app.notification().builder().title(&input.title);
        if let Some(body) = &input.body {
            builder = builder.body(body);
        }
        let _ = builder.show();
    }

    let _ = prune_expired(&pool).await;
    let _ = enforce_cap(&pool).await;
    refresh_badge(app, &pool).await;
    let _ = app.emit("notification:new", ());

    if !inserted {
        return Ok(None);
    }

    let record = sqlx::query_as::<_, Notification>(
        "SELECT id, category, severity, title, body, action_type, action_payload, read_at, created_at, expires_at FROM notifications WHERE id = ?",
    )
    .bind(&id)
    .fetch_one(&pool)
    .await?;

    Ok(Some(record))
}

pub async fn list(
    pool: &SqlitePool,
    limit: i64,
    only_unread: bool,
) -> AppResult<Vec<Notification>> {
    let sql = if only_unread {
        "SELECT id, category, severity, title, body, action_type, action_payload, read_at, created_at, expires_at
         FROM notifications WHERE read_at IS NULL ORDER BY created_at DESC LIMIT ?"
    } else {
        "SELECT id, category, severity, title, body, action_type, action_payload, read_at, created_at, expires_at
         FROM notifications ORDER BY created_at DESC LIMIT ?"
    };
    let rows = sqlx::query_as::<_, Notification>(sql)
        .bind(limit)
        .fetch_all(pool)
        .await?;
    Ok(rows)
}

pub async fn count_unread(pool: &SqlitePool) -> AppResult<i64> {
    let count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM notifications WHERE read_at IS NULL")
        .fetch_one(pool)
        .await?;
    Ok(count)
}

pub async fn mark_read(pool: &SqlitePool, id: &str) -> AppResult<()> {
    let now = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_default();
    sqlx::query("UPDATE notifications SET read_at = ? WHERE id = ? AND read_at IS NULL")
        .bind(&now)
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn mark_all_read(pool: &SqlitePool) -> AppResult<()> {
    let now = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_default();
    sqlx::query("UPDATE notifications SET read_at = ? WHERE read_at IS NULL")
        .bind(&now)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn delete(pool: &SqlitePool, id: &str) -> AppResult<()> {
    sqlx::query("DELETE FROM notifications WHERE id = ?")
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn clear_all(pool: &SqlitePool) -> AppResult<()> {
    sqlx::query("DELETE FROM notifications")
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn prune_expired(pool: &SqlitePool) -> AppResult<()> {
    let now = OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_default();
    sqlx::query("DELETE FROM notifications WHERE expires_at IS NOT NULL AND expires_at < ?")
        .bind(&now)
        .execute(pool)
        .await?;
    Ok(())
}

async fn enforce_cap(pool: &SqlitePool) -> AppResult<()> {
    sqlx::query(
        "DELETE FROM notifications WHERE id IN (
            SELECT id FROM notifications ORDER BY created_at DESC LIMIT -1 OFFSET ?
        )",
    )
    .bind(MAX_ITEMS)
    .execute(pool)
    .await?;
    Ok(())
}
