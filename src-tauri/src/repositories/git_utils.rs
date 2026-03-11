use std::path::Path;
use std::process::Command;
use crate::error::{AppError, AppResult};

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
        return Err(AppError::Internal("Failed to get repository name".to_string()));
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
        return Err(AppError::Internal("Failed to get default branch".to_string()));
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
        return Err(AppError::Internal(format!("Failed to clone repository: {}", err)));
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
        return Err(AppError::Internal(format!("Failed to checkout branch: {}", err)));
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
        return Err(AppError::Internal(format!("Failed to create branch: {}", err)));
    }

    Ok(())
}
