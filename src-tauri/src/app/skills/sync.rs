use chrono::Utc;
use std::collections::HashSet;
use tauri::{AppHandle, State};

use crate::app::support::error::AppResult;
use crate::state::AppState;

use super::types::InstalledSkill;
use super::{parse_frontmatter, title_case};

pub async fn sync(
    app_handle: AppHandle,
    workspace_path: Option<String>,
    state: State<'_, AppState>,
) -> AppResult<Vec<InstalledSkill>> {
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    let dirs = super::skill_dirs(&app_handle, workspace_path.as_deref());
    let mut seen: HashSet<String> = HashSet::new();
    let mut scanned_scopes: HashSet<&'static str> = HashSet::new();

    for (dir, scope) in &dirs {
        let entries = match std::fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        scanned_scopes.insert(scope);

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
                "INSERT OR IGNORE INTO skills (id, name, description, enabled, icon_path, installed_at, source_path, scope, customer_id) VALUES (?, ?, ?, 1, NULL, ?, ?, ?, ?)",
            )
            .bind(&dir_name)
            .bind(&name)
            .bind(&description)
            .bind(&now)
            .bind(&source_path)
            .bind(scope)
            .bind(&customer_id)
            .execute(&state.pool().await?)
            .await?;

            sqlx::query(
                "UPDATE skills SET name = ?, description = ?, source_path = ?, scope = ? WHERE id = ? AND customer_id IS ? AND scope != 'global'",
            )
            .bind(&name)
            .bind(&description)
            .bind(&source_path)
            .bind(scope)
            .bind(&dir_name)
            .bind(&customer_id)
            .execute(&state.pool().await?)
            .await?;

            seen.insert(dir_name);
        }
    }

    prune_missing(&state, &scanned_scopes, &seen, &customer_id).await?;

    super::get::get(state).await
}

async fn prune_missing(
    state: &State<'_, AppState>,
    scanned_scopes: &HashSet<&'static str>,
    seen: &HashSet<String>,
    customer_id: &Option<String>,
) -> AppResult<()> {
    if scanned_scopes.is_empty() {
        return Ok(());
    }

    let scope_list: Vec<&&str> = scanned_scopes.iter().collect();
    let seen_list: Vec<&String> = seen.iter().collect();

    let mut sql = String::from("DELETE FROM skills WHERE customer_id IS ? AND scope IN (");
    sql.push_str(&vec!["?"; scope_list.len()].join(","));
    sql.push(')');
    if !seen_list.is_empty() {
        sql.push_str(" AND id NOT IN (");
        sql.push_str(&vec!["?"; seen_list.len()].join(","));
        sql.push(')');
    }

    let mut query = sqlx::query(&sql).bind(customer_id);
    for scope in &scope_list {
        query = query.bind(**scope);
    }
    for id in &seen_list {
        query = query.bind(*id);
    }
    query.execute(&state.pool().await?).await?;

    Ok(())
}
