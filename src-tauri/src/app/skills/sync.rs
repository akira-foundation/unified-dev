use tauri::State;
use std::collections::HashSet;
use std::path::PathBuf;
use chrono::Utc;

use crate::state::AppState;
use crate::app::support::error::AppResult;

use super::types::InstalledSkill;

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

fn parse_frontmatter(content: &str) -> (Option<String>, Option<String>) {
    let mut name: Option<String> = None;
    let mut description: Option<String> = None;
    let mut lines = content.lines();
    if lines.next().map(str::trim) != Some("---") {
        return (name, description);
    }
    for line in lines {
        let trimmed = line.trim();
        if trimmed == "---" {
            break;
        }
        if let Some(rest) = trimmed.strip_prefix("name:") {
            name = Some(rest.trim().to_string());
        } else if let Some(rest) = trimmed.strip_prefix("description:") {
            description = Some(rest.trim().to_string());
        }
    }
    (name, description)
}

fn title_case(s: &str) -> String {
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

pub async fn sync(state: State<'_, AppState>) -> AppResult<Vec<InstalledSkill>> {
    let mut seen: HashSet<String> = HashSet::new();

    for dir in skill_dirs() {
        let entries = match std::fs::read_dir(&dir) {
            Ok(e) => e,
            Err(_) => continue,
        };

        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }
            let dir_name = match path.file_name().and_then(|n| n.to_str()) {
                Some(n) => n.to_string(),
                None => continue,
            };
            if dir_name.starts_with('.') || seen.contains(&dir_name) {
                continue;
            }
            let skill_md = path.join("SKILL.md");
            if !skill_md.exists() {
                continue;
            }
            let content = match std::fs::read_to_string(&skill_md) {
                Ok(c) => c,
                Err(_) => continue,
            };

            let (parsed_name, parsed_desc) = parse_frontmatter(&content);
            let name = parsed_name.unwrap_or_else(|| title_case(&dir_name));
            let description = parsed_desc.unwrap_or_default();
            let source_path = path.to_string_lossy().to_string();
            let now = Utc::now().to_rfc3339();

            sqlx::query(
                "INSERT OR IGNORE INTO skills (id, name, description, enabled, icon_path, installed_at, source_path) VALUES (?, ?, ?, 1, NULL, ?, ?)",
            )
            .bind(&dir_name)
            .bind(&name)
            .bind(&description)
            .bind(&now)
            .bind(&source_path)
            .execute(&state.db_pool)
            .await?;

            sqlx::query("UPDATE skills SET name = ?, description = ?, source_path = ? WHERE id = ?")
                .bind(&name)
                .bind(&description)
                .bind(&source_path)
                .bind(&dir_name)
                .execute(&state.db_pool)
                .await?;

            seen.insert(dir_name);
        }
    }

    super::get::get(state).await
}
