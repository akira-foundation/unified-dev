pub use crate::app::filesystem::FileNode;
pub use crate::app::repositories::{FileChange, PrInfo};

#[tauri::command]
pub async fn list_files(workspace_path: String, directory_path: String) -> Result<Vec<FileNode>, String> {
    crate::app::filesystem::list(workspace_path, directory_path).await
}

#[tauri::command]
pub async fn read_file(path: String) -> Result<String, String> {
    crate::app::filesystem::read(path).await
}

#[tauri::command]
pub async fn search_files(workspace_path: String, query: String) -> Result<Vec<FileNode>, String> {
    crate::app::filesystem::search(workspace_path, query).await
}

#[tauri::command]
pub async fn get_workspace_changes(workspace_path: String) -> Result<Vec<FileChange>, String> {
    crate::app::repositories::changes(workspace_path).await
}

#[tauri::command]
pub async fn create_draft_pr(workspace_path: String, branch_name: String, title: String) -> Result<String, String> {
    crate::app::repositories::create_pr(workspace_path, branch_name, title).await
}

#[tauri::command]
pub async fn discard_file_changes(workspace_path: String, filename: String) -> Result<(), String> {
    crate::app::repositories::discard_changes(workspace_path, filename).await
}

#[tauri::command]
pub async fn check_pr_url(workspace_path: String) -> Result<PrInfo, String> {
    crate::app::repositories::check_pr(workspace_path).await
}

#[tauri::command]
pub async fn run_workspace_command(workspace_path: String, command: String) -> Result<String, String> {
    crate::app::repositories::run_command(workspace_path, command).await
}
