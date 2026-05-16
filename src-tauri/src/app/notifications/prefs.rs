use serde::{Deserialize, Serialize};
use sqlx::SqlitePool;

use crate::app::support::error::AppResult;

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct NotificationPref {
    pub category: String,
    pub in_app: bool,
    pub os_notify: bool,
    pub updated_at: String,
}

pub async fn list(pool: &SqlitePool) -> AppResult<Vec<NotificationPref>> {
    let rows = sqlx::query_as::<_, NotificationPref>(
        "SELECT category, in_app, os_notify, updated_at FROM notification_prefs ORDER BY category",
    )
    .fetch_all(pool)
    .await?;
    Ok(rows)
}

pub async fn get(pool: &SqlitePool, category: &str) -> AppResult<Option<NotificationPref>> {
    let row = sqlx::query_as::<_, NotificationPref>(
        "SELECT category, in_app, os_notify, updated_at FROM notification_prefs WHERE category = ?",
    )
    .bind(category)
    .fetch_optional(pool)
    .await?;
    Ok(row)
}

pub async fn upsert(
    pool: &SqlitePool,
    category: &str,
    in_app: bool,
    os_notify: bool,
) -> AppResult<()> {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO notification_prefs (category, in_app, os_notify, updated_at)
         VALUES (?, ?, ?, ?)
         ON CONFLICT(category) DO UPDATE SET
            in_app = excluded.in_app,
            os_notify = excluded.os_notify,
            updated_at = excluded.updated_at",
    )
    .bind(category)
    .bind(in_app as i64)
    .bind(os_notify as i64)
    .bind(&now)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn resolve(pool: &SqlitePool, category: &str) -> (bool, bool) {
    match get(pool, category).await {
        Ok(Some(pref)) => (pref.in_app, pref.os_notify),
        _ => (true, true),
    }
}
