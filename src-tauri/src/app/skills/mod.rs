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

pub fn parse_frontmatter(content: &str) -> (Option<String>, Option<String>) {
    let mut name: Option<String> = None;
    let mut description: Option<String> = None;
    let mut lines = content.lines().peekable();
    if lines.next().map(str::trim) != Some("---") {
        return (name, description);
    }
    while let Some(line) = lines.next() {
        let trimmed = line.trim();
        if trimmed == "---" {
            break;
        }
        if let Some(rest) = trimmed.strip_prefix("name:") {
            name = Some(rest.trim().to_string());
        } else if let Some(rest) = trimmed.strip_prefix("description:") {
            let value = rest.trim();
            if value.is_empty() || value.starts_with('>') || value.starts_with('|') {
                let mut parts: Vec<String> = Vec::new();
                while let Some(next) = lines.peek() {
                    if next.trim() == "---" {
                        break;
                    }
                    if next.trim().is_empty() {
                        lines.next();
                        continue;
                    }
                    if !(next.starts_with(' ') || next.starts_with('\t')) {
                        break;
                    }
                    parts.push(next.trim().to_string());
                    lines.next();
                }
                description = Some(parts.join(" "));
            } else {
                description = Some(value.to_string());
            }
        }
    }
    (name, description)
}

pub fn title_case(s: &str) -> String {
    s.split('-')
        .map(|w| {
            let mut c = w.chars();
            match c.next() {
                None => String::new(),
                Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

pub async fn load_content(pool: &SqlitePool) -> Vec<(String, String)> {
    let customer_id = crate::app::auth::current_customer_id(pool).await;
    let rows: Vec<(String, String, String)> = sqlx::query_as(
        "SELECT id, name, source_path FROM skills WHERE enabled = 1 AND customer_id = ? ORDER BY scope DESC, name COLLATE NOCASE",
    )
    .bind(&customer_id)
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

#[cfg(test)]
mod tests {
    use super::parse_frontmatter;

    #[test]
    fn folded_block_scalar_description() {
        let md = "---\nname: commit-guard\ndescription: >-\n  Line one\n  line two\n---\nbody";
        let (name, desc) = parse_frontmatter(md);
        assert_eq!(name.as_deref(), Some("commit-guard"));
        assert_eq!(desc.as_deref(), Some("Line one line two"));
    }

    #[test]
    fn literal_block_scalar_description() {
        let md = "---\ndescription: |\n  alpha\n  beta\n---";
        let (_, desc) = parse_frontmatter(md);
        assert_eq!(desc.as_deref(), Some("alpha beta"));
    }

    #[test]
    fn plain_inline_description() {
        let (name, desc) = parse_frontmatter("---\nname: foo\ndescription: hello world\n---");
        assert_eq!(name.as_deref(), Some("foo"));
        assert_eq!(desc.as_deref(), Some("hello world"));
    }

    #[test]
    fn no_frontmatter() {
        let (name, desc) = parse_frontmatter("# title\nbody");
        assert!(name.is_none() && desc.is_none());
    }
}
