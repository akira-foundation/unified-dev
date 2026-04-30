use std::path::Path;

use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct PrCheck {
    pub name: String,
    pub state: String,
    pub bucket: String,
    pub link: Option<String>,
    pub workflow: Option<String>,
    #[serde(rename = "startedAt")]
    pub started_at: Option<String>,
    #[serde(rename = "completedAt")]
    pub completed_at: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct PrCiStatus {
    pub checks: Vec<PrCheck>,
    pub total: usize,
    pub passing: usize,
    pub failing: usize,
    pub pending: usize,
}

pub async fn check_pr_ci(workspace_path: String) -> Result<PrCiStatus, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Ok(empty_status());
    }

    let output = tokio::process::Command::new("gh")
        .args([
            "pr",
            "checks",
            "--json",
            "name,state,bucket,link,workflow,startedAt,completedAt",
        ])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run gh pr checks: {e}"))?;

    if !output.status.success() {
        let code = output.status.code().unwrap_or(-1);
        if code == 8 {
            // pending — gh exits 8 but JSON valid
        } else {
            return Ok(empty_status());
        }
    }

    let raw = String::from_utf8_lossy(&output.stdout);
    let checks: Vec<PrCheck> = serde_json::from_str(raw.trim()).unwrap_or_default();

    let passing = checks.iter().filter(|c| c.bucket == "pass").count();
    let failing = checks.iter().filter(|c| c.bucket == "fail" || c.bucket == "cancel").count();
    let pending = checks.iter().filter(|c| c.bucket == "pending").count();

    Ok(PrCiStatus {
        total: checks.len(),
        passing,
        failing,
        pending,
        checks,
    })
}

fn empty_status() -> PrCiStatus {
    PrCiStatus {
        checks: Vec::new(),
        total: 0,
        passing: 0,
        failing: 0,
        pending: 0,
    }
}
