use std::path::Path;
use std::process::Command;

use crate::app::support::error::{AppError, AppResult};

pub fn is_git_repository(path: &Path) -> bool {
    path.join(".git").exists()
}

pub fn get_repository_name(path: &Path) -> AppResult<String> {
    let output = Command::new("git")
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
    let output = Command::new("git")
        .current_dir(path)
        .args(["rev-parse", "--abbrev-ref", "HEAD"])
        .output()
        .map_err(AppError::Io)?;

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
        .map_err(AppError::Io)?;

    if !output.status.success() {
        return Err(AppError::Internal(format!(
            "Failed to clone repository: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    Ok(())
}

pub fn clone_from_url(url: &str, destination: &Path) -> AppResult<()> {
    let output = Command::new("git")
        .args(["clone", url, &destination.to_string_lossy()])
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
    let output = Command::new("git")
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

pub fn is_github_url(url: &str) -> bool {
    url.contains("github.com")
}

pub fn repo_name_from_url(url: &str) -> Option<String> {
    let last = url.trim_end_matches('/').split('/').last()?;
    let name = last.trim_end_matches(".git");
    if name.is_empty() {
        None
    } else {
        Some(name.to_string())
    }
}

pub fn set_remote_url(path: &Path, remote: &str, url: &str) -> AppResult<()> {
    let output = Command::new("git")
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
