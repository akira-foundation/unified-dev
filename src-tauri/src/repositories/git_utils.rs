use crate::error::{AppError, AppResult};
use std::path::Path;
use std::process::Command;

pub fn is_git_repository(path: &Path) -> bool {
    path.join(".git").exists()
}

pub fn get_repository_name(path: &Path) -> AppResult<String> {
    let output = Command::new("git")
        .current_dir(path)
        .args(["rev-parse", "--show-toplevel"])
        .output()
        .map_err(|e| AppError::Io(e))?;

    if !output.status.success() {
        return Err(AppError::Internal(
            "Failed to get repository name".to_string(),
        ));
    }

    let top_level = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let name = Path::new(&top_level)
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();

    Ok(name)
}

pub fn get_default_branch(path: &Path) -> AppResult<String> {
    let output = Command::new("git")
        .current_dir(path)
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .map_err(|e| AppError::Io(e))?;

    if !output.status.success() {
        return Err(AppError::Internal(
            "Failed to get default branch".to_string(),
        ));
    }

    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

pub fn clone_repository(source: &Path, destination: &Path) -> AppResult<()> {
    let output = Command::new("git")
        .args([
            "clone",
            &source.to_string_lossy(),
            &destination.to_string_lossy(),
        ])
        .output()
        .map_err(|e| AppError::Io(e))?;

    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        return Err(AppError::Internal(format!(
            "Failed to clone repository: {}",
            err
        )));
    }

    Ok(())
}

pub fn checkout_branch(path: &Path, branch: &str) -> AppResult<()> {
    let output = Command::new("git")
        .current_dir(path)
        .args(["checkout", branch])
        .output()
        .map_err(|e| AppError::Io(e))?;

    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        return Err(AppError::Internal(format!(
            "Failed to checkout branch: {}",
            err
        )));
    }

    Ok(())
}

pub fn create_branch(path: &Path, branch: &str) -> AppResult<()> {
    let output = Command::new("git")
        .current_dir(path)
        .args(["checkout", "-b", branch])
        .output()
        .map_err(|e| AppError::Io(e))?;

    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        return Err(AppError::Internal(format!(
            "Failed to create branch: {}",
            err
        )));
    }

    Ok(())
}

/// Returns the URL of `remote` in `path`, or `None` if it doesn't exist / command fails.
pub fn get_remote_url(path: &Path, remote: &str) -> Option<String> {
    let output = Command::new("git")
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

/// Returns true if the URL looks like a real GitHub remote (SSH or HTTPS).
pub fn is_github_url(url: &str) -> bool {
    url.contains("github.com")
}

/// Replaces the URL of `remote` in `path` with `url`.
pub fn set_remote_url(path: &Path, remote: &str, url: &str) -> AppResult<()> {
    let output = Command::new("git")
        .current_dir(path)
        .args(["remote", "set-url", remote, url])
        .output()
        .map_err(|e| AppError::Io(e))?;

    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        return Err(AppError::Internal(format!(
            "Failed to set remote URL: {}",
            err
        )));
    }

    Ok(())
}
