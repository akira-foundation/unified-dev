use tauri::State;
use std::path::PathBuf;

use crate::state::AppState;
use crate::support::error::AppResult;

fn skill_dirs() -> Vec<PathBuf> {
    let home = match dirs::home_dir() {
        Some(h) => h,
        None => return vec![],
    };
    vec![
        home.join(".codex").join("skills"),
        home.join(".claude").join("skills"),
        home.join(".config").join("opencode").join("skills"),
        home.join(".agents").join("skills"),
    ]
}

fn icons_dir() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join(".agents").join("skills").join(".icons"))
}

pub async fn uninstall_skill(id: String, state: State<'_, AppState>) -> AppResult<()> {
    for dir in skill_dirs() {
        let skill_dir = dir.join(&id);
        if skill_dir.is_dir() {
            let _ = std::fs::remove_dir_all(&skill_dir);
        }
    }

    if let Some(icons) = icons_dir() {
        for ext in &["png", "jpg", "jpeg", "webp", "svg"] {
            let icon = icons.join(format!("{}.{}", id, ext));
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
