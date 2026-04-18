use std::path::Path;
use std::process::Command;

use super::RemoteProvider;
use crate::app::support::error::{AppError, AppResult};

pub struct BitbucketProvider;

impl RemoteProvider for BitbucketProvider {
    fn clone(&self, nwo: &str, destination: &Path) -> AppResult<()> {
        let url = format!("https://bitbucket.org/{nwo}.git");
        let output = Command::new("git")
            .args(["clone", "--quiet", &url, &destination.to_string_lossy()])
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
}
