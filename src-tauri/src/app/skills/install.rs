use tauri::{AppHandle, Manager, State};
use std::io::Read;
use chrono::Utc;

use crate::state::AppState;
use crate::app::support::error::AppResult;

use super::types::InstalledSkill;
use super::{parse_frontmatter, title_case};

pub async fn install(
    skill_id: String,
    repo_url: String,
    app_handle: AppHandle,
    state: State<'_, AppState>,
) -> AppResult<InstalledSkill> {
    let repo_url = repo_url.trim_end_matches('/').to_string();
    let zip_url = format!("{}/archive/refs/heads/main.zip", repo_url);

    let bytes = reqwest::get(&zip_url)
        .await
        .map_err(|e| crate::app::support::error::AppError::Internal(e.to_string()))?
        .bytes()
        .await
        .map_err(|e| crate::app::support::error::AppError::Internal(e.to_string()))?;

    let cursor = std::io::Cursor::new(bytes.as_ref());
    let mut archive = zip::ZipArchive::new(cursor)
        .map_err(|e| crate::app::support::error::AppError::Internal(e.to_string()))?;

    let mut name = String::new();
    let mut description = String::new();
    let now = Utc::now().to_rfc3339();

    let global_skills_dir = app_handle
        .path()
        .app_data_dir()
        .map_err(|e| crate::app::support::error::AppError::Internal(e.to_string()))?
        .join("skills");

    let mut skill_files: Vec<(String, Vec<u8>)> = Vec::new();
    let mut strip_prefix = String::new();

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)
            .map_err(|e| crate::app::support::error::AppError::Internal(e.to_string()))?;
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
                .map_err(|e| crate::app::support::error::AppError::Internal(e.to_string()))?;

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
        return Err(crate::app::support::error::AppError::Internal(format!(
            "Skill '{}' not found in the repository zip",
            skill_id
        )));
    }

    let skill_dir = global_skills_dir.join(&skill_id);
    std::fs::create_dir_all(&skill_dir)
        .map_err(|e| crate::app::support::error::AppError::Internal(e.to_string()))?;

    for (relative, buf) in &skill_files {
        let dest = skill_dir.join(relative);
        if let Some(parent) = dest.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let _ = std::fs::write(&dest, buf);
    }

    let installed_source = skill_dir.to_string_lossy().to_string();

    if name.is_empty() {
        name = title_case(&skill_id);
    }

    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    sqlx::query(
        "INSERT INTO skills (id, name, description, enabled, icon_path, installed_at, source_path, scope, customer_id)
         VALUES (?, ?, ?, 1, NULL, ?, ?, 'global', ?)
         ON CONFLICT(id, customer_id) DO UPDATE SET
           name = excluded.name,
           description = excluded.description,
           source_path = excluded.source_path,
           installed_at = excluded.installed_at,
           scope = 'global'",
    )
    .bind(&skill_id)
    .bind(&name)
    .bind(&description)
    .bind(&now)
    .bind(&installed_source)
    .bind(&customer_id)
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
        scope: "global".to_string(),
    })
}
