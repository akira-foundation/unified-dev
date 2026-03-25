use std::collections::HashSet;
use std::io::Read;
use std::path::PathBuf;

use chrono::Utc;
use serde::Serialize;
use tauri::State;

use crate::error::AppResult;
use crate::state::AppState;

#[derive(Debug, Serialize, Clone)]
pub struct InstalledSkill {
    pub id: String,
    pub name: String,
    pub description: String,
    pub enabled: bool,
    pub icon_path: Option<String>,
    pub installed_at: String,
    pub source_path: String,
}

/// Directories to scan for installed skills, in priority order.
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

/// Icon storage directory.
fn icons_dir() -> Option<PathBuf> {
    dirs::home_dir().map(|h| h.join(".agents").join("skills").join(".icons"))
}

/// Parse `name` and `description` from YAML frontmatter in a SKILL.md.
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

/// Scan filesystem for skills and upsert into the DB.
/// Skills already in the DB keep their `enabled` and `icon_path`.
/// Returns the full list from the DB after sync.
#[tauri::command]
pub async fn sync_skills(state: State<'_, AppState>) -> AppResult<Vec<InstalledSkill>> {
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
            if dir_name.starts_with('.') {
                continue;
            }
            if seen.contains(&dir_name) {
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
                "INSERT OR IGNORE INTO skills (id, name, description, enabled, icon_path, installed_at, source_path)
                 VALUES (?, ?, ?, 1, NULL, ?, ?)",
            )
            .bind(&dir_name)
            .bind(&name)
            .bind(&description)
            .bind(&now)
            .bind(&source_path)
            .execute(&state.db_pool)
            .await?;

            sqlx::query(
                "UPDATE skills SET name = ?, description = ?, source_path = ? WHERE id = ?",
            )
            .bind(&name)
            .bind(&description)
            .bind(&source_path)
            .bind(&dir_name)
            .execute(&state.db_pool)
            .await?;

            seen.insert(dir_name);
        }
    }

    get_skills(state).await
}

/// Read the full skill list from the DB.
#[tauri::command]
pub async fn get_skills(state: State<'_, AppState>) -> AppResult<Vec<InstalledSkill>> {
    let rows = sqlx::query_as::<_, (String, String, String, bool, Option<String>, String, String)>(
        "SELECT id, name, description, enabled, icon_path, installed_at, source_path
         FROM skills ORDER BY name COLLATE NOCASE",
    )
    .fetch_all(&state.db_pool)
    .await?;

    Ok(rows
        .into_iter()
        .map(|(id, name, description, enabled, icon_path, installed_at, source_path)| {
            InstalledSkill { id, name, description, enabled, icon_path, installed_at, source_path }
        })
        .collect())
}

/// Persist the enabled/disabled toggle for a skill.
#[tauri::command]
pub async fn set_skill_enabled(
    id: String,
    enabled: bool,
    state: State<'_, AppState>,
) -> AppResult<()> {
    sqlx::query("UPDATE skills SET enabled = ? WHERE id = ?")
        .bind(enabled)
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}

/// Save a custom icon image for a skill.
/// Copies the image bytes to ~/.agents/skills/.icons/{id}.{ext}
/// and persists the absolute path in the DB.
/// Returns the absolute path to the saved icon.
#[tauri::command]
pub async fn set_skill_icon(
    id: String,
    data: Vec<u8>,
    extension: String,
    state: State<'_, AppState>,
) -> AppResult<String> {
    let icons = match icons_dir() {
        Some(d) => d,
        None => return Err(crate::error::AppError::Internal("Cannot resolve home dir".into())),
    };
    std::fs::create_dir_all(&icons)?;

    let filename = format!("{}.{}", id, extension);
    let dest = icons.join(&filename);
    std::fs::write(&dest, &data)?;

    let path_str = dest.to_string_lossy().to_string();
    sqlx::query("UPDATE skills SET icon_path = ? WHERE id = ?")
        .bind(&path_str)
        .bind(&id)
        .execute(&state.db_pool)
        .await?;

    Ok(path_str)
}

/// Download and install a skill from a GitHub repo URL into all 4 skill dirs.
/// Expects a GitHub repo URL like https://github.com/org/repo
/// The repo must contain a SKILL.md at the root (single-skill repos)
/// or this installs the matching subfolder by skill_id.
/// Overwrites existing installations. Registers in DB.
#[tauri::command]
pub async fn install_skill(
    skill_id: String,
    repo_url: String,
    state: State<'_, AppState>,
) -> AppResult<InstalledSkill> {
    let repo_url = repo_url.trim_end_matches('/').to_string();
    let zip_url = format!("{}/archive/refs/heads/main.zip", repo_url);

    let bytes = reqwest::get(&zip_url)
        .await
        .map_err(|e| crate::error::AppError::Internal(e.to_string()))?
        .bytes()
        .await
        .map_err(|e| crate::error::AppError::Internal(e.to_string()))?;

    let cursor = std::io::Cursor::new(bytes.as_ref());
    let mut archive = zip::ZipArchive::new(cursor)
        .map_err(|e| crate::error::AppError::Internal(e.to_string()))?;

    let mut name = String::new();
    let mut description = String::new();
    let mut installed_source = String::new();
    let now = Utc::now().to_rfc3339();
    let dirs = skill_dirs();

    let mut skill_files: Vec<(String, Vec<u8>)> = Vec::new();
    let mut strip_prefix = String::new();

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)
            .map_err(|e| crate::error::AppError::Internal(e.to_string()))?;
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
                .map_err(|e| crate::error::AppError::Internal(e.to_string()))?;

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
        return Err(crate::error::AppError::Internal(format!(
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

/// Uninstall a skill: removes its directory from all skill dirs and deletes from DB.
#[tauri::command]
pub async fn uninstall_skill(
    id: String,
    state: State<'_, AppState>,
) -> AppResult<()> {
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

/// Legacy command kept for compatibility.
#[tauri::command]
pub fn list_installed_skills() -> Vec<serde_json::Value> {
    vec![]
}
