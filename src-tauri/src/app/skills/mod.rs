pub mod discover;
pub mod get;
pub mod install;
pub mod list_installed;
pub mod set_enabled;
pub mod set_icon;
pub mod sync;
pub mod types;
pub mod uninstall;

pub use discover::fetch_recommended;
pub use discover::fetch_from_repo;
pub use get::get;
pub use install::install;
pub use list_installed::list_installed;
pub use set_enabled::set_enabled;
pub use set_icon::set_icon;
pub use sync::sync;
pub use types::InstalledSkill;
pub use uninstall::uninstall;

use std::path::PathBuf;
use sqlx::SqlitePool;
use tauri::Manager;

pub fn skill_dirs(app_handle: &tauri::AppHandle, workspace_path: Option<&str>) -> Vec<(PathBuf, &'static str)> {
    let mut dirs: Vec<(PathBuf, &'static str)> = Vec::new();

    if let Some(ws) = workspace_path {
        let ws_path = PathBuf::from(ws);
        if !ws_path.as_os_str().is_empty() {
            dirs.push((ws_path.join(".skills"), "project"));
        }
    }

    if let Ok(home) = app_handle.path().home_dir() {
        dirs.push((home.join(".claude").join("skills"), "local"));
        dirs.push((home.join(".codex"), "local"));
    }

    if let Ok(app_data) = app_handle.path().app_data_dir() {
        dirs.push((app_data.join("skills"), "global"));
    }

    dirs
}

pub async fn load_content(pool: &SqlitePool) -> Vec<(String, String)> {
    let rows: Vec<(String, String, String)> = sqlx::query_as(
        "SELECT id, name, source_path FROM skills WHERE enabled = 1 ORDER BY scope DESC, name COLLATE NOCASE",
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default();

    let mut seen = std::collections::HashSet::new();
    let mut result = Vec::new();

    for (id, name, source_path) in rows {
        if seen.contains(&id) {
            continue;
        }
        seen.insert(id);

        let skill_md = PathBuf::from(&source_path).join("SKILL.md");
        if let Ok(content) = std::fs::read_to_string(&skill_md) {
            if !content.trim().is_empty() {
                result.push((name, content));
            }
        }
    }

    result
}
