use std::collections::HashSet;
use std::path::PathBuf;

use serde::Serialize;

#[derive(Debug, Serialize, Clone)]
pub struct InstalledSkill {
    pub id: String,
    pub name: String,
    pub description: String,
}

/// Directories to scan for installed skills, in priority order.
/// Each entry is resolved relative to the user's home directory.
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

/// Parse `name` and `description` fields from YAML frontmatter in a SKILL.md file.
/// Frontmatter is delimited by `---` lines at the start of the file.
fn parse_frontmatter(content: &str) -> (Option<String>, Option<String>) {
    let mut name: Option<String> = None;
    let mut description: Option<String> = None;

    let mut lines = content.lines();

    // First line must be `---`
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

#[tauri::command]
pub fn list_installed_skills() -> Vec<InstalledSkill> {
    let mut skills: Vec<InstalledSkill> = Vec::new();
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

            // Skip system skill directories
            let dir_name = match path.file_name().and_then(|n| n.to_str()) {
                Some(n) => n.to_string(),
                None => continue,
            };
            if dir_name.starts_with('.') {
                continue;
            }

            // Deduplicate by directory name across locations
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

            let name = parsed_name.unwrap_or_else(|| {
                // Fallback: title-case the directory name
                dir_name
                    .split('-')
                    .map(|w| {
                        let mut c = w.chars();
                        match c.next() {
                            None => String::new(),
                            Some(f) => f.to_uppercase().collect::<String>() + c.as_str(),
                        }
                    })
                    .collect::<Vec<_>>()
                    .join(" ")
            });

            let description = parsed_desc.unwrap_or_default();

            seen.insert(dir_name.clone());
            skills.push(InstalledSkill {
                id: dir_name,
                name,
                description,
            });
        }
    }

    // Sort alphabetically by name
    skills.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));

    skills
}
