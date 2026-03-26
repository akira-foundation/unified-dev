pub use crate::app::workspaces::{FileChange, FileNode, PrInfo};

#[tauri::command]
pub async fn list_files(workspace_path: String, directory_path: String) -> Result<Vec<FileNode>, String> {
    crate::app::workspaces::list_files(workspace_path, directory_path).await
}

#[tauri::command]
pub async fn read_file(path: String) -> Result<String, String> {
    crate::app::workspaces::read_file(path).await
}

#[tauri::command]
pub async fn search_files(workspace_path: String, query: String) -> Result<Vec<FileNode>, String> {
    crate::app::workspaces::search_files(workspace_path, query).await
}

#[tauri::command]
pub async fn get_workspace_changes(workspace_path: String) -> Result<Vec<FileChange>, String> {
    crate::app::workspaces::get_workspace_changes(workspace_path).await
}

#[tauri::command]
pub async fn create_draft_pr(workspace_path: String, branch_name: String, title: String) -> Result<String, String> {
    crate::app::workspaces::create_draft_pr(workspace_path, branch_name, title).await
}

#[tauri::command]
pub async fn discard_file_changes(workspace_path: String, filename: String) -> Result<(), String> {
    crate::app::workspaces::discard_file_changes(workspace_path, filename).await
}

#[tauri::command]
pub async fn check_pr_url(workspace_path: String) -> Result<PrInfo, String> {
    crate::app::workspaces::check_pr_url(workspace_path).await
}

#[tauri::command]
pub async fn run_workspace_command(workspace_path: String, command: String) -> Result<String, String> {
    crate::app::workspaces::run_workspace_command(workspace_path, command).await
}
