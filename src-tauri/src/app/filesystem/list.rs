use std::fs;
use std::path::Path;

use crate::app::filesystem::types::FileNode;

pub async fn list(workspace_path: String, directory_path: String) -> Result<Vec<FileNode>, String> {
    let root = Path::new(&workspace_path);
    let dir = Path::new(&directory_path);

    if !dir.exists() {
        return Err("Directory does not exist".to_string());
    }

    let mut nodes = Vec::new();
    let entries = fs::read_dir(dir).map_err(|e| e.to_string())?;

    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let metadata = entry.metadata().map_err(|e| e.to_string())?;
        let name = entry.file_name().to_string_lossy().to_string();

        if name == ".git" || name == "node_modules" || name == "target" || name == ".DS_Store" {
            continue;
        }

        let is_dir = metadata.is_dir();
        let full_path = entry.path();
        let relative_path = full_path
            .strip_prefix(root)
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| name.clone());

        nodes.push(FileNode {
            name,
            path: relative_path,
            is_dir,
            children: if is_dir { Some(Vec::new()) } else { None },
        });
    }

    nodes.sort_by(|a, b| {
        if a.is_dir != b.is_dir {
            b.is_dir.cmp(&a.is_dir)
        } else {
            a.name.to_lowercase().cmp(&b.name.to_lowercase())
        }
    });

    Ok(nodes)
}
