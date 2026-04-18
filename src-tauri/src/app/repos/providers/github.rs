use std::path::Path;
use std::process::Command;

use super::RemoteProvider;
use crate::app::support::bin::resolve_binary;
use crate::app::support::error::{AppError, AppResult};

pub struct GitHubProvider;

impl GitHubProvider {
    fn get_token(gh: &Path) -> Option<String> {
        let output = Command::new(gh).args(["auth", "token"]).output().ok()?;
        if !output.status.success() {
            return None;
        }
        let token = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if token.is_empty() {
            None
        } else {
            Some(token)
        }
    }
}

impl RemoteProvider for GitHubProvider {
    fn clone(&self, nwo: &str, destination: &Path) -> AppResult<()> {
        let gh = resolve_binary("gh").ok_or(AppError::GhNotInstalled)?;

        let token = Self::get_token(&gh).ok_or(AppError::GhNotAuthenticated)?;

        let git =
            resolve_binary("git").ok_or_else(|| AppError::Internal("git not found".to_string()))?;

        let url = format!("https://x-access-token:{token}@github.com/{nwo}.git");

        let output = Command::new(&git)
            .args(["clone", "--quiet", &url, &destination.to_string_lossy()])
            .output()
            .map_err(AppError::Io)?;

        if !output.status.success() {
            if destination.exists() {
                let _ = std::fs::remove_dir_all(destination);
            }
            return Err(AppError::Internal(format!(
                "Failed to clone repository: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }

        Ok(())
    }
}
