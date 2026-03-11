use crate::agents::providers::registry;
use std::fs;
use std::path::{Path, PathBuf};
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct FileNode {
    pub name: String,
    pub path: String,
    pub is_dir: bool,
    pub children: Option<Vec<FileNode>>,
}

#[tauri::command]
pub async fn get_available_models() -> Result<registry::ModelRegistry, String> {
    Ok(registry::get_or_build_registry().await)
}

#[tauri::command]
pub async fn list_files(workspace_path: String, directory_path: String) -> Result<Vec<FileNode>, String> {
    let root = Path::new(&workspace_path);
    let dir = Path::new(&directory_path);
    
    if !dir.exists() {
        return Err("Directory does not exist".to_string());
    }

    read_dir_shallow(dir, root)
}

#[tauri::command]
pub async fn read_file(path: String) -> Result<String, String> {
    let path = Path::new(&path);
    if !path.exists() {
        return Err("File does not exist".to_string());
    }

    fs::read_to_string(path).map_err(|e| e.to_string())
}

fn read_dir_shallow(current_path: &Path, root: &Path) -> Result<Vec<FileNode>, String> {
    let mut nodes = Vec::new();
    let entries = fs::read_dir(current_path).map_err(|e| e.to_string())?;

    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let metadata = entry.metadata().map_err(|e| e.to_string())?;
        let name = entry.file_name().to_string_lossy().to_string();
        
        // Skip common ignored files/folders
        if name == ".git" || name == "node_modules" || name == "target" || name == ".DS_Store" {
            continue;
        }

        let is_dir = metadata.is_dir();
        let full_path = entry.path();
        let relative_path = full_path.strip_prefix(root)
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_else(|_| name.clone());

        nodes.push(FileNode {
            name,
            path: relative_path,
            is_dir,
            children: if is_dir { Some(Vec::new()) } else { None },
        });
    }

    // Sort: directories first, then alphabetically
    nodes.sort_by(|a, b| {
        if a.is_dir != b.is_dir {
            b.is_dir.cmp(&a.is_dir)
        } else {
            a.name.to_lowercase().cmp(&b.name.to_lowercase())
        }
    });

    Ok(nodes)
}
