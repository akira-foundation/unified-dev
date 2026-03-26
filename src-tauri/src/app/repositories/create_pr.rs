use std::path::Path;

pub async fn create_pr(workspace_path: String, branch_name: String, title: String) -> Result<String, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Err(format!("Workspace path does not exist: {workspace_path}"));
    }

    let run = |args: &[&str]| -> Result<String, String> {
        let out = std::process::Command::new(args[0])
            .args(&args[1..])
            .current_dir(workspace)
            .output()
            .map_err(|e| format!("Failed to run {:?}: {e}", args[0]))?;
        let stdout = String::from_utf8_lossy(&out.stdout).to_string();
        let stderr = String::from_utf8_lossy(&out.stderr).to_string();
        if !out.status.success() {
            return Err(if stderr.is_empty() { stdout } else { stderr });
        }
        Ok(stdout)
    };

    run(&["git", "add", "-A"])?;
    let status = run(&["git", "status", "--porcelain"])?;
    if !status.trim().is_empty() {
        run(&["git", "commit", "-m", &format!("chore: agent changes for '{title}'")])?;
    }
    run(&["git", "push", "-u", "origin", &branch_name])?;

    let pr_body = format!("This draft PR was created automatically by the Akira agent.\n\nThread: {title}");
    let pr_url = run(&["gh", "pr", "create", "--draft", "--title", &title, "--body", &pr_body, "--head", &branch_name])?;

    Ok(pr_url.trim().to_string())
}
