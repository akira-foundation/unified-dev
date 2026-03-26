use std::path::Path;

use crate::app::repos::types::FileChange;

pub async fn changes(workspace_path: String) -> Result<Vec<FileChange>, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Err(format!("Workspace path does not exist: {workspace_path}"));
    }

    let git_dir = workspace.join(".git");
    if !git_dir.exists() {
        return Ok(vec![]);
    }

    let status_output = tokio::process::Command::new("git")
        .args(["status", "--porcelain"])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run git status: {e}"))?;

    let status_text = String::from_utf8_lossy(&status_output.stdout);
    let mut changes: Vec<FileChange> = Vec::new();

    for line in status_text.lines() {
        if line.len() < 4 {
            continue;
        }
        let xy = &line[0..2];
        let filename = line[3..].trim().to_string();
        let status = match xy.trim() {
            "M" | "MM" | " M" => "modified",
            "A" | "AM" => "added",
            "D" | " D" => "deleted",
            "R" => "modified",
            _ => "modified",
        }
        .to_string();

        let diff = if status == "deleted" {
            let show_output = tokio::process::Command::new("git")
                .args(["show", &format!("HEAD:{filename}")])
                .current_dir(workspace)
                .output()
                .await
                .ok();
            show_output.and_then(|o| {
                if o.status.success() {
                    let content = String::from_utf8_lossy(&o.stdout).to_string();
                    Some(content.lines().map(|l| format!("-{l}")).collect::<Vec<_>>().join("\n"))
                } else {
                    None
                }
            })
        } else {
            let diff_output = tokio::process::Command::new("git")
                .args(["diff", "HEAD", "--", &filename])
                .current_dir(workspace)
                .output()
                .await
                .ok();

            let diff_text = diff_output
                .and_then(|o| if o.stdout.is_empty() { None } else { Some(o.stdout) })
                .map(|b| String::from_utf8_lossy(&b).to_string());

            if diff_text.is_none() || diff_text.as_deref() == Some("") {
                let cached_output = tokio::process::Command::new("git")
                    .args(["diff", "--cached", "--", &filename])
                    .current_dir(workspace)
                    .output()
                    .await
                    .ok();
                cached_output.and_then(|o| if o.stdout.is_empty() { None } else { Some(String::from_utf8_lossy(&o.stdout).to_string()) })
            } else {
                diff_text
            }
        };

        changes.push(FileChange { filename, status, diff });
    }

    Ok(changes)
}
