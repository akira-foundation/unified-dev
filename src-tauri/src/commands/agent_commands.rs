use crate::agents::registry;
use crate::chat::message::{get_messages, Message};
use crate::chat::session;
use crate::chat::stream::emit_error;
use crate::error::AppResult;
use crate::state::AppState;
use std::fs;
use std::path::Path;
use serde::{Deserialize, Serialize};
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
    silent: Option<bool>,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    let pool = state.db_pool.clone();
    let app = app.clone();
    let thread_id_err = thread_id.clone();
    let silent = silent.unwrap_or(false);

    tokio::spawn(async move {
        if let Err(e) = session::run(thread_id, message, model, silent, pool, app.clone()).await {
            emit_error(&app, &thread_id_err, &e.to_string());
        }
    });

    Ok(())
}

/// Returns the list of files changed in the workspace (relative to HEAD) along with their diffs.
#[derive(Debug, Serialize, Deserialize)]
pub struct FileChange {
    pub filename: String,
    pub status: String,
    pub diff: Option<String>,
}

#[tauri::command]
pub async fn get_workspace_changes(workspace_path: String) -> Result<Vec<FileChange>, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Err(format!("Workspace path does not exist: {workspace_path}"));
    }

    // Check if it's a git repo
    let git_dir = workspace.join(".git");
    if !git_dir.exists() {
        return Ok(vec![]);
    }

    // Run `git status --porcelain` to get changed files and their status codes
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
        // Porcelain format: XY filename  (XY is 2-char status, space, then filename)
        let xy = &line[0..2];
        let filename = line[3..].trim().to_string();

        let status = match xy.trim() {
            "M" | "MM" | " M" => "modified",
            "A" | "AM" => "added",
            "D" | " D" => "deleted",
            "R" => "modified", // renamed — treat as modified
            _ => "modified",
        }
        .to_string();

        // Get the diff for this file. For deleted files use `git show HEAD:file`.
        let diff = if status == "deleted" {
            // Show what was in HEAD
            let show_output = tokio::process::Command::new("git")
                .args(["show", &format!("HEAD:{filename}")])
                .current_dir(workspace)
                .output()
                .await
                .ok();
            show_output.and_then(|o| {
                if o.status.success() {
                    let content = String::from_utf8_lossy(&o.stdout).to_string();
                    // Wrap as a deletion diff
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
            // `git diff HEAD -- <file>` covers both staged and unstaged changes
            let diff_output = tokio::process::Command::new("git")
                .args(["diff", "HEAD", "--", &filename])
                .current_dir(workspace)
                .output()
                .await
                .ok();

            let diff_text = diff_output
                .and_then(|o| if o.stdout.is_empty() { None } else { Some(o.stdout) })
                .map(|b| String::from_utf8_lossy(&b).to_string());

            // If `git diff HEAD` produced nothing (e.g. newly staged file not yet committed)
            // fall back to `git diff --cached -- <file>`
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

/// Creates a draft pull request on GitHub for the given branch and returns the PR URL.
/// Steps:
///   1. git add -A && git commit (if there are uncommitted changes)
///   2. git push -u origin <branch>
///   3. gh pr create --draft
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

    // 1. Stage all changes
    run(&["git", "add", "-A"])?;

    // 2. Commit if there is anything staged
    let status = run(&["git", "status", "--porcelain"])?;
    if !status.trim().is_empty() {
        run(&["git", "commit", "-m", &format!("chore: agent changes for '{title}'")])?;
    }

    // 3. Push branch to origin (set upstream on first push)
    run(&["git", "push", "-u", "origin", &branch_name])?;

    // 4. Create draft PR via GitHub CLI
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

/// Discards all uncommitted changes to a specific file by running `git checkout HEAD -- <file>`.
/// For untracked (added) files, removes the file entirely.
#[tauri::command]
pub async fn discard_file_changes(workspace_path: String, filename: String) -> Result<(), String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Err(format!("Workspace path does not exist: {workspace_path}"));
    }

    // Check if the file is tracked (modified/deleted) or untracked (added)
    let status_output = tokio::process::Command::new("git")
        .args(["status", "--porcelain", "--", &filename])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run git status: {e}"))?;

    let status_line = String::from_utf8_lossy(&status_output.stdout);
    let xy = status_line.get(0..2).unwrap_or("").trim();

    if xy == "??" || xy == "A" || xy == "AM" {
        // Untracked or newly added — just delete the file
        let file_path = workspace.join(&filename);
        if file_path.exists() {
            fs::remove_file(&file_path).map_err(|e| format!("Failed to delete file: {e}"))?;
        }
    } else {
        // Tracked — restore to HEAD
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

/// Checks whether a GitHub PR exists for the current branch in the given workspace.
/// Returns `{ url, is_draft }` if a PR exists, or `{ url: "", is_draft: false }` if not.
#[derive(Debug, Serialize)]
pub struct PrInfo {
    pub url: String,
    pub is_draft: bool,
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
        // Format: "https://github.com/.../pull/1|false"
        if let Some((url, draft_str)) = raw.split_once('|') {
            return Ok(PrInfo {
                url: url.to_string(),
                is_draft: draft_str.trim() == "true",
            });
        }
        Ok(PrInfo { url: raw, is_draft: false })
    } else {
        // No PR found (gh exits non-zero when there is no PR)
        Ok(PrInfo { url: String::new(), is_draft: false })
    }
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
