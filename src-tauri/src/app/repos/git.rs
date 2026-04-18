use std::path::Path;
use std::process::Command;

use crate::app::support::bin::resolve_binary;
use crate::app::support::error::{AppError, AppResult};

fn git_bin() -> Option<std::path::PathBuf> {
    resolve_binary("git")
}

pub fn is_git_repository(path: &Path) -> bool {
    if !path.exists() {
        return false;
    }
    let Some(git) = git_bin() else { return false };
    Command::new(git)
        .current_dir(path)
        .args(["rev-parse", "--git-dir"])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

/// Returns true only if the path is a git repo AND has at least one commit
/// (i.e. a complete, usable clone — not a partial/interrupted one).
pub fn is_valid_clone(path: &Path) -> bool {
    if !path.exists() {
        return false;
    }
    let Some(git) = git_bin() else { return false };
    // git rev-parse HEAD fails if there are no commits (empty or incomplete clone)
    Command::new(git)
        .current_dir(path)
        .args(["rev-parse", "HEAD"])
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}

pub fn get_repository_name(path: &Path) -> AppResult<String> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let output = Command::new(git)
        .current_dir(path)
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(
            "Failed to get repository name".to_string(),
        ));
    }

    let top_level = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok(Path::new(&top_level)
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string())
}

pub fn get_default_branch(path: &Path) -> AppResult<String> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;

    let symbolic = Command::new(&git)
        .current_dir(path)
        .args(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
        .output()
        .map_err(AppError::Io)?;

    if symbolic.status.success() {
        let raw = String::from_utf8_lossy(&symbolic.stdout);
        let branch = raw.trim().strip_prefix("origin/").unwrap_or(raw.trim());
        if !branch.is_empty() {
            return Ok(branch.to_string());
        }
    }

    let rev = Command::new(&git)
        .current_dir(path)
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .map_err(AppError::Io)?;

    if rev.status.success() {
        let branch = String::from_utf8_lossy(&rev.stdout);
        let branch = branch.trim();
        if !branch.is_empty() && branch != "HEAD" {
            return Ok(branch.to_string());
        }
    }

    let ls = Command::new(&git)
        .current_dir(path)
        .args(["ls-remote", "--symref", "origin", "HEAD"])
        .output()
        .map_err(AppError::Io)?;

    if ls.status.success() {
        let out = String::from_utf8_lossy(&ls.stdout);
        for line in out.lines() {
            if let Some(rest) = line.strip_prefix("ref: refs/heads/") {
                let branch = rest.split_whitespace().next().unwrap_or("").trim();
                if !branch.is_empty() {
                    return Ok(branch.to_string());
                }
            }
        }
    }

    // Final fallback: read local HEAD symref directly (works for empty repos that have no commits
    // yet — git clone still sets HEAD → refs/heads/<default> from the remote's advertised HEAD).
    let local_head = Command::new(&git)
        .current_dir(path)
        .args(["symbolic-ref", "HEAD"])
        .output()
        .map_err(AppError::Io)?;

    if local_head.status.success() {
        let raw = String::from_utf8_lossy(&local_head.stdout);
        let raw = raw.trim();
        if let Some(branch) = raw.strip_prefix("refs/heads/") {
            if !branch.is_empty() {
                return Ok(branch.to_string());
            }
        }
    }

    Err(AppError::Internal(format!(
        "Failed to get default branch [path={} symbolic={} rev={} ls={}]",
        path.display(),
        String::from_utf8_lossy(&symbolic.stderr).trim(),
        String::from_utf8_lossy(&rev.stderr).trim(),
        String::from_utf8_lossy(&ls.stderr).trim(),
    )))
}

pub fn clone_repository(source: &Path, destination: &Path) -> AppResult<()> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let output = Command::new(git)
        .args([
            "clone",
            &source.to_string_lossy(),
            &destination.to_string_lossy(),
        ])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to clone repository: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

pub fn create_branch(path: &Path, branch: &str) -> AppResult<()> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let output = Command::new(git)
        .current_dir(path)
        .args(["checkout", "-b", branch])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to create branch: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

pub fn fetch_branch(path: &Path, remote: &str, branch: &str) -> AppResult<()> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let output = Command::new(git)
        .current_dir(path)
        .args(["fetch", remote, branch])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to fetch branch: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

pub fn checkout_remote_branch(path: &Path, remote: &str, branch: &str) -> AppResult<()> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let remote_branch = format!("{remote}/{branch}");
    let output = Command::new(git)
        .current_dir(path)
        .args(["checkout", "-B", branch, &remote_branch])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to checkout branch: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

pub fn fetch_ref(path: &Path, remote: &str, git_ref: &str) -> AppResult<()> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let output = Command::new(git)
        .current_dir(path)
        .args(["fetch", remote, git_ref])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to fetch ref: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

pub fn checkout_fetch_head(path: &Path) -> AppResult<()> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let output = Command::new(git)
        .current_dir(path)
        .args(["checkout", "--detach", "FETCH_HEAD"])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to checkout fetched ref: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

pub fn fetch_commit(path: &Path, remote: &str, sha: &str) -> AppResult<()> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let output = Command::new(git)
        .current_dir(path)
        .args(["fetch", remote, sha])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to fetch commit: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

pub fn get_remote_url(path: &Path, remote: &str) -> Option<String> {
    let git = git_bin()?;
    let output = Command::new(git)
        .current_dir(path)
        .args(["remote", "get-url", remote])
        .output()
        .ok()?;

    if output.status.success() {
        let url = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if url.is_empty() {
            None
        } else {
            Some(url)
        }
    } else {
        None
    }
}

pub fn is_github_url(url: &str) -> bool {
    url.contains("github.com")
}

pub fn repo_name_from_url(url: &str) -> Option<String> {
    let last = url.trim_end_matches('/').split('/').next_back()?;
    let name = last.trim_end_matches(".git");
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

pub fn set_remote_url(path: &Path, remote: &str, url: &str) -> AppResult<()> {
    let git = git_bin().ok_or_else(|| AppError::Internal("git not found".to_string()))?;
    let output = Command::new(git)
        .current_dir(path)
        .args(["remote", "set-url", remote, url])
        .output()
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to set remote URL: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}
