use std::path::{Path, PathBuf};

use tauri::Manager;

use crate::app::support::error::{AppError, AppResult};

const PENDING_FILE: &str = "restore.pending.sqlite";
const FLAG_FILE: &str = "restore.flag";
const SQLITE_HEADER: &[u8; 16] = b"SQLite format 3\0";

pub fn stage(app: &tauri::AppHandle, source: &Path) -> AppResult<PathBuf> {
    if !source.is_file() {
        return Err(AppError::Internal(format!(
            "restore source not found: {}",
            source.display()
        )));
    }

    validate_sqlite_header(source)?;

    let target_db = crate::database::database_path(app)?;
    let app_dir = target_db
        .parent()
        .ok_or_else(|| AppError::Internal("app data dir unavailable".into()))?
        .to_path_buf();

    std::fs::create_dir_all(&app_dir)?;
    let pending = app_dir.join(PENDING_FILE);
    let flag = app_dir.join(FLAG_FILE);

    std::fs::copy(source, &pending)?;
    std::fs::write(&flag, target_db.to_string_lossy().as_bytes())?;

    Ok(target_db)
}

pub fn apply_pending(app: &tauri::AppHandle) -> AppResult<bool> {
    let app_dir = app.path().app_data_dir()?;
    let pending = app_dir.join(PENDING_FILE);
    let flag = app_dir.join(FLAG_FILE);

    if !flag.exists() || !pending.exists() {
        let _ = std::fs::remove_file(&pending);
        let _ = std::fs::remove_file(&flag);
        return Ok(false);
    }

    let target_raw = std::fs::read_to_string(&flag)?;
    let target = PathBuf::from(target_raw.trim());

    if target.exists() {
        let safety = target.with_extension("pre-restore.sqlite");
        let _ = std::fs::remove_file(&safety);
        std::fs::rename(&target, &safety)?;
    }

    std::fs::rename(&pending, &target)?;
    std::fs::remove_file(&flag)?;

    Ok(true)
}

fn validate_sqlite_header(path: &Path) -> AppResult<()> {
    let mut header = [0u8; 16];
    let bytes = std::fs::read(path)?;
    if bytes.len() < header.len() {
        return Err(AppError::Internal("restore source is too small to be a sqlite database".into()));
    }
    header.copy_from_slice(&bytes[..16]);
    if &header != SQLITE_HEADER {
        return Err(AppError::Internal("restore source is not a sqlite database".into()));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validate_sqlite_header_accepts_valid_header() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("db.sqlite");
        let mut bytes = Vec::from(SQLITE_HEADER.as_slice());
        bytes.extend_from_slice(&[0u8; 64]);
        std::fs::write(&path, &bytes).unwrap();

        validate_sqlite_header(&path).expect("valid header must pass");
    }

    #[test]
    fn validate_sqlite_header_rejects_garbage() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("not-sqlite.bin");
        std::fs::write(&path, b"not a sqlite file at all xxxxxxxxxxx").unwrap();

        let err = validate_sqlite_header(&path).unwrap_err();
        assert!(format!("{err}").contains("not a sqlite database"));
    }

    #[test]
    fn validate_sqlite_header_rejects_tiny_file() {
        let tmp = tempfile::tempdir().unwrap();
        let path = tmp.path().join("tiny.bin");
        std::fs::write(&path, b"abc").unwrap();

        let err = validate_sqlite_header(&path).unwrap_err();
        assert!(format!("{err}").contains("too small"));
    }
}
