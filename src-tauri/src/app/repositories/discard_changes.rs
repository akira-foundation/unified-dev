use std::path::Path;

pub async fn discard_changes(workspace_path: String, filename: String) -> Result<(), String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Err(format!("Workspace path does not exist: {workspace_path}"));
    }

    let status_output = tokio::process::Command::new("git")
        .args(["status", "--porcelain", "--", &filename])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run git status: {e}"))?;

    let status_line = String::from_utf8_lossy(&status_output.stdout);
    let xy = status_line.get(0..2).unwrap_or("").trim();

    if xy == "??" || xy == "A" || xy == "AM" {
        let file_path = workspace.join(&filename);
        if file_path.exists() {
            std::fs::remove_file(&file_path).map_err(|e| format!("Failed to delete file: {e}"))?;
        }
    } else {
        let out = tokio::process::Command::new("git")
            .args(["checkout", "HEAD", "--", &filename])
            .current_dir(workspace)
            .output()
            .await
            .map_err(|e| format!("Failed to run git checkout: {e}"))?;

        if !out.status.success() {
            let stderr = String::from_utf8_lossy(&out.stderr).to_string();
            return Err(if stderr.is_empty() { format!("git checkout failed for {filename}") } else { stderr });
        }
    }

    Ok(())
}
