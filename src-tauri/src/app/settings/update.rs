use std::path::{Path, PathBuf};

use chrono::Utc;
use serde::{Deserialize, Serialize};
use sqlx::FromRow;

use crate::app::support::error::{AppError, AppResult};

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
#[serde(rename_all = "camelCase")]
pub struct UpdateSettings {
    #[sqlx(rename = "backup_before_update")]
    #[serde(rename = "backupBeforeUpdate")]
    pub backup_before_update: bool,
    #[sqlx(rename = "backup_path")]
    #[serde(rename = "backupPath")]
    pub backup_path: Option<String>,
}

pub async fn get(pool: &sqlx::SqlitePool) -> AppResult<UpdateSettings> {
    let row = sqlx::query_as::<_, UpdateSettings>(
        "SELECT backup_before_update, backup_path FROM update_settings WHERE id = 'local' LIMIT 1",
    )
    .fetch_optional(pool)
    .await?;

    Ok(row.unwrap_or(UpdateSettings {
        backup_before_update: true,
        backup_path: None,
    }))
}

pub async fn set(pool: &sqlx::SqlitePool, settings: UpdateSettings) -> AppResult<UpdateSettings> {
    let now = Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO update_settings (id, backup_before_update, backup_path, updated_at)
         VALUES ('local', ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
            backup_before_update = excluded.backup_before_update,
            backup_path = excluded.backup_path,
            updated_at = excluded.updated_at",
    )
    .bind(settings.backup_before_update)
    .bind(settings.backup_path.as_deref())
    .bind(&now)
    .execute(pool)
    .await?;

    get(pool).await
}

pub async fn perform_backup(
    pool: &sqlx::SqlitePool,
    db_path: &Path,
    target_version: &str,
) -> AppResult<Option<PathBuf>> {
    let settings = get(pool).await?;
    if !settings.backup_before_update {
        return Ok(None);
    }

    let base_dir = match settings.backup_path {
        Some(path) if !path.is_empty() => PathBuf::from(path),
        _ => dirs::desktop_dir().ok_or_else(|| {
            AppError::Internal("desktop directory unavailable for default backup path".into())
        })?,
    };

    std::fs::create_dir_all(&base_dir)?;

    let stamp = Utc::now().format("%Y%m%d-%H%M%S");
    let filename = format!("unified-dev-pre-{target_version}-{stamp}.sqlite");
    let dest = base_dir.join(filename);

    sqlx::query("VACUUM INTO ?").bind(dest.to_string_lossy().as_ref()).execute(pool).await?;

    let _ = db_path;
    Ok(Some(dest))
}
