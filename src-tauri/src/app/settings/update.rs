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

    let escaped = dest.to_string_lossy().replace('\'', "''");
    sqlx::query(&format!("VACUUM INTO '{escaped}'")).execute(pool).await?;

    let _ = db_path;
    Ok(Some(dest))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::setup_test_db;

    #[tokio::test]
    async fn perform_backup_returns_none_when_disabled() {
        let pool = setup_test_db().await;
        let disabled = UpdateSettings { backup_before_update: false, backup_path: None };
        set(&pool, disabled).await.expect("disable backup");

        let tmp = tempfile::tempdir().expect("tempdir");
        let result = perform_backup(&pool, tmp.path(), "1.2.3").await.expect("perform_backup");

        assert!(result.is_none());
    }

    #[tokio::test]
    async fn perform_backup_writes_file_to_configured_path() {
        let tmp = tempfile::tempdir().expect("tempdir");
        let source = tmp.path().join("source.sqlite");
        let url = format!("sqlite://{}?mode=rwc", source.display());
        let pool = sqlx::sqlite::SqlitePoolOptions::new()
            .max_connections(1)
            .connect(&url)
            .await
            .expect("open source");
        sqlx::migrate!("./src/database/migrations")
            .run(&pool)
            .await
            .expect("migrate");

        let dest_dir = tmp.path().join("backups");
        let configured = UpdateSettings {
            backup_before_update: true,
            backup_path: Some(dest_dir.to_string_lossy().to_string()),
        };
        set(&pool, configured).await.expect("enable backup");

        let dest = perform_backup(&pool, &source, "9.9.9")
            .await
            .expect("perform_backup")
            .expect("dest path");

        assert!(dest.exists(), "backup file must exist: {dest:?}");
        let name = dest.file_name().and_then(|n| n.to_str()).unwrap_or("");
        assert!(name.starts_with("unified-dev-pre-9.9.9-"));
        assert!(name.ends_with(".sqlite"));
    }

    #[tokio::test]
    async fn set_persists_path_and_toggle() {
        let pool = setup_test_db().await;
        let settings = UpdateSettings {
            backup_before_update: false,
            backup_path: Some("/tmp/custom".to_string()),
        };

        let saved = set(&pool, settings).await.expect("set");

        assert!(!saved.backup_before_update);
        assert_eq!(saved.backup_path.as_deref(), Some("/tmp/custom"));

        let reloaded = get(&pool).await.expect("get");
        assert!(!reloaded.backup_before_update);
        assert_eq!(reloaded.backup_path.as_deref(), Some("/tmp/custom"));
    }
}
