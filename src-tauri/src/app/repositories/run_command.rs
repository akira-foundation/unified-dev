use std::path::Path;

pub async fn run_command(workspace_path: String, command: String) -> Result<String, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Err(format!("Workspace path does not exist: {workspace_path}"));
    }

    let parts: Vec<&str> = command.trim().splitn(8, ' ').collect();
    if parts.is_empty() {
        return Err("Empty command".to_string());
    }

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
        return Err(if stderr.is_empty() { format!("Command exited with status {}", output.status) } else { stderr });
    }

    Ok(if stderr.is_empty() { stdout } else { format!("{stdout}\n{stderr}") })
}
