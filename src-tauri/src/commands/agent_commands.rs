use crate::agents::providers::registry;
use crate::chat::messages::{get_messages, Message};
use crate::chat::send_message::send_message as send_message_logic;
use crate::chat::stream::emit_error;
use crate::error::AppResult;
use crate::state::AppState;
use std::fs;
use std::path::Path;
use serde::Serialize;
use tauri::{AppHandle, State};

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

#[tauri::command]
pub async fn search_files(workspace_path: String, query: String) -> Result<Vec<FileNode>, String> {
    let root = Path::new(&workspace_path);
    if !root.exists() {
        return Err("Workspace does not exist".to_string());
    }

    let mut results = Vec::new();
    search_recursive(root, root, &query, &mut results)?;
    
    // Limit results for performance
    results.truncate(100);
    
    Ok(results)
}

fn search_recursive(current_path: &Path, root: &Path, query: &str, results: &mut Vec<FileNode>) -> Result<(), String> {
    let entries = fs::read_dir(current_path).map_err(|e| e.to_string())?;

    for entry in entries {
        let entry = entry.map_err(|e| e.to_string())?;
        let name = entry.file_name().to_string_lossy().to_string();
        
        // Skip common ignored files/folders
        if name == ".git" || name == "node_modules" || name == "target" || name == ".DS_Store" {
            continue;
        }

        let metadata = entry.metadata().map_err(|e| e.to_string())?;
        let is_dir = metadata.is_dir();
        let full_path = entry.path();
        let relative_path = full_path.strip_prefix(root)
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

/// Returns all persisted messages for a thread, oldest-first (capped at 40).
#[tauri::command]
pub async fn agents_get_messages(
    thread_id: String,
    state: State<'_, AppState>,
) -> AppResult<Vec<Message>> {
    get_messages(&thread_id, &state.db_pool).await
}

/// Saves the user message, streams the model response via Tauri events,
/// then saves the completed assistant response. Returns immediately — the
/// stream runs in a background task.
///
/// Frontend events emitted during the stream:
///   "agent-stream-token" → { thread_id, token }
///   "agent-stream-done"  → { thread_id }
///   "agent-stream-error" → { thread_id, error }
#[tauri::command]
pub async fn agents_send_message(
    thread_id: String,
    message: String,
    model: String,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    let pool = state.db_pool.clone();
    let app = app.clone();
    let thread_id_err = thread_id.clone();

    tokio::spawn(async move {
        if let Err(e) = send_message_logic(thread_id, message, model, pool, app.clone()).await {
            emit_error(&app, &thread_id_err, &e.to_string());
        }
    });

    Ok(())
}

/// Run a shell command inside the given workspace directory and return its stdout+stderr output.
/// Only a safe allow-list of base commands is accepted.
#[tauri::command]
pub async fn run_workspace_command(workspace_path: String, command: String) -> Result<String, String> {
    // Validate workspace path exists
    let workspace = std::path::Path::new(&workspace_path);
    if !workspace.exists() {
        return Err(format!("Workspace path does not exist: {workspace_path}"));
    }

    // Split command into program + args (simple whitespace split — no shell injection)
    let parts: Vec<&str> = command.trim().splitn(8, ' ').collect();
    if parts.is_empty() {
        return Err("Empty command".to_string());
    }

    // Allow-list of safe base programs
    let allowed = ["git", "ls", "cat", "find", "wc", "echo"];
    if !allowed.contains(&parts[0]) {
        return Err(format!("Command '{}' is not in the allow-list", parts[0]));
    }

    let output = tokio::process::Command::new(parts[0])
        .args(&parts[1..])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run command: {e}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() && stdout.is_empty() {
        return Err(if stderr.is_empty() {
            format!("Command exited with status {}", output.status)
        } else {
            stderr
        });
    }

    Ok(if stderr.is_empty() {
        stdout
    } else {
        format!("{stdout}\n{stderr}")
    })
}
