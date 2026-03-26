use tauri::State;
use std::io::Read;
use std::path::PathBuf;
use chrono::Utc;

use crate::state::AppState;
use crate::support::error::AppResult;

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

pub async fn install(skill_id: String, repo_url: String, state: State<'_, AppState>) -> AppResult<InstalledSkill> {
    let repo_url = repo_url.trim_end_matches('/').to_string();
    let zip_url = format!("{}/archive/refs/heads/main.zip", repo_url);

    let bytes = reqwest::get(&zip_url)
        .await
        .map_err(|e| crate::support::error::AppError::Internal(e.to_string()))?
        .bytes()
        .await
        .map_err(|e| crate::support::error::AppError::Internal(e.to_string()))?;

    let cursor = std::io::Cursor::new(bytes.as_ref());
    let mut archive = zip::ZipArchive::new(cursor)
        .map_err(|e| crate::support::error::AppError::Internal(e.to_string()))?;

    let mut name = String::new();
    let mut description = String::new();
    let mut installed_source = String::new();
    let now = Utc::now().to_rfc3339();
    let dirs = skill_dirs();

    let mut skill_files: Vec<(String, Vec<u8>)> = Vec::new();
    let mut strip_prefix = String::new();

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)
            .map_err(|e| crate::support::error::AppError::Internal(e.to_string()))?;
        let raw_name = file.name().to_string();

        let needle = format!("/{}/", skill_id);
        if let Some(pos) = raw_name.find(&needle) {
            if strip_prefix.is_empty() {
                strip_prefix = raw_name[..pos + needle.len()].to_string();
            }
            let relative = &raw_name[strip_prefix.len()..];
            if relative.is_empty() || file.is_dir() {
                continue;
            }
            let mut buf = Vec::new();
            file.read_to_end(&mut buf)
                .map_err(|e| crate::support::error::AppError::Internal(e.to_string()))?;

            if relative == "SKILL.md" {
                let content = String::from_utf8_lossy(&buf).to_string();
                let (n, d) = parse_frontmatter(&content);
                name = n.unwrap_or_else(|| title_case(&skill_id));
                description = d.unwrap_or_default();
            }

            skill_files.push((relative.to_string(), buf));
        }
    }

    if skill_files.is_empty() {
        return Err(crate::support::error::AppError::Internal(format!(
            "Skill '{}' not found in the repository zip",
            skill_id
        )));
    }

    for target_dir in &dirs {
        let skill_dir = target_dir.join(&skill_id);
        if let Err(e) = std::fs::create_dir_all(&skill_dir) {
            eprintln!("Failed to create dir {:?}: {}", skill_dir, e);
            continue;
        }
        for (relative, buf) in &skill_files {
            let dest = skill_dir.join(relative);
            if let Some(parent) = dest.parent() {
                let _ = std::fs::create_dir_all(parent);
            }
            let _ = std::fs::write(&dest, buf);
        }
        if installed_source.is_empty() {
            installed_source = skill_dir.to_string_lossy().to_string();
        }
    }

    if name.is_empty() {
        name = title_case(&skill_id);
    }

    sqlx::query(
        "INSERT INTO skills (id, name, description, enabled, icon_path, installed_at, source_path)
         VALUES (?, ?, ?, 1, NULL, ?, ?)
         ON CONFLICT(id) DO UPDATE SET
           name = excluded.name,
           description = excluded.description,
           source_path = excluded.source_path,
           installed_at = excluded.installed_at",
    )
    .bind(&skill_id)
    .bind(&name)
    .bind(&description)
    .bind(&now)
    .bind(&installed_source)
    .execute(&state.db_pool)
    .await?;

    Ok(InstalledSkill {
        id: skill_id,
        name,
        description,
        enabled: true,
        icon_path: None,
        installed_at: now,
        source_path: installed_source,
    })
}
