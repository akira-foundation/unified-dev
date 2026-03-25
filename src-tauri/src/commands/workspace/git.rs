use std::fs;
use std::path::Path;

use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct FileChange {
    pub filename: String,
    pub status: String,
    pub diff: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PrInfo {
    pub url: String,
    pub is_draft: bool,
}

#[tauri::command]
pub async fn get_workspace_changes(workspace_path: String) -> Result<Vec<FileChange>, String> {
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
                    Some(
                        content
                            .lines()
                            .map(|l| format!("-{l}"))
                            .collect::<Vec<_>>()
                            .join("\n"),
                    )
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
                cached_output.and_then(|o| {
                    if o.stdout.is_empty() {
                        None
                    } else {
                        Some(String::from_utf8_lossy(&o.stdout).to_string())
                    }
                })
            } else {
                diff_text
            }
        };

        changes.push(FileChange { filename, status, diff });
    }

    Ok(changes)
}

#[tauri::command]
pub async fn create_draft_pr(
    workspace_path: String,
    branch_name: String,
    title: String,
) -> Result<String, String> {
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

    let pr_body = format!(
        "This draft PR was created automatically by the Akira agent.\n\nThread: {title}"
    );
    let pr_url = run(&[
        "gh", "pr", "create",
        "--draft",
        "--title", &title,
        "--body", &pr_body,
        "--head", &branch_name,
    ])?;

    Ok(pr_url.trim().to_string())
}

#[tauri::command]
pub async fn discard_file_changes(workspace_path: String, filename: String) -> Result<(), String> {
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
            fs::remove_file(&file_path).map_err(|e| format!("Failed to delete file: {e}"))?;
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
            return Err(if stderr.is_empty() {
                format!("git checkout failed for {filename}")
            } else {
                stderr
            });
        }
    }

    Ok(())
}

#[tauri::command]
pub async fn check_pr_url(workspace_path: String) -> Result<PrInfo, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Ok(PrInfo { url: String::new(), is_draft: false });
    }

    let output = tokio::process::Command::new("gh")
        .args(["pr", "view", "--json", "url,isDraft", "--jq", "[.url, (.isDraft | tostring)] | join(\"|\")" ])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run gh pr view: {e}"))?;

    if output.status.success() {
        let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if let Some((url, draft_str)) = raw.split_once('|') {
            return Ok(PrInfo {
                url: url.to_string(),
                is_draft: draft_str.trim() == "true",
            });
        }
        Ok(PrInfo { url: raw, is_draft: false })
    } else {
        Ok(PrInfo { url: String::new(), is_draft: false })
    }
}

/// Only a safe allow-list of base commands is accepted.
#[tauri::command]
pub async fn run_workspace_command(workspace_path: String, command: String) -> Result<String, String> {
    let workspace = std::path::Path::new(&workspace_path);
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
