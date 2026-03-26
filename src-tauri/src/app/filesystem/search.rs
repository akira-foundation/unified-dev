use std::fs;
use std::path::Path;

use crate::app::filesystem::types::FileNode;

pub async fn search(workspace_path: String, query: String) -> Result<Vec<FileNode>, String> {
    let root = Path::new(&workspace_path);
    if !root.exists() {
        return Err("Workspace does not exist".to_string());
    }

    let mut results = Vec::new();
    search_recursive(root, root, &query, &mut results)?;
    results.truncate(100);
    Ok(results)
}

fn search_recursive(current_path: &Path, root: &Path, query: &str, results: &mut Vec<FileNode>) -> Result<(), String> {
    let entries = fs::read_dir(current_path).map_err(|e| e.to_string())?;

    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let name = entry.file_name().to_string_lossy().to_string();

        if name == ".git" || name == "node_modules" || name == "target" || name == ".DS_Store" {
            continue;
        }

        let metadata = entry.metadata().map_err(|e| e.to_string())?;
        let is_dir = metadata.is_dir();
        let full_path = entry.path();
        let relative_path = full_path
            .strip_prefix(root)
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| name.clone());

        if name.to_lowercase().contains(&query.to_lowercase()) {
            results.push(FileNode {
                name: name.clone(),
                path: relative_path.clone(),
                is_dir,
                children: if is_dir { Some(Vec::new()) } else { None },
            });
        }

        if is_dir {
            search_recursive(&full_path, root, query, results)?;
        }

        if results.len() >= 100 {
            break;
        }
    }

    Ok(())
}
