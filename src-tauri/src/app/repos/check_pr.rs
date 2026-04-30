use std::path::Path;

use crate::app::repos::types::PrInfo;

fn empty() -> PrInfo {
    PrInfo {
        url: String::new(),
        is_draft: false,
        state: String::new(),
        merged_at: None,
    }
}

pub async fn check_pr(workspace_path: String) -> Result<PrInfo, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Ok(empty());
    }

    let output = tokio::process::Command::new("gh")
        .args(["pr", "view", "--json", "url,isDraft,state,mergedAt"])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run gh pr view: {e}"))?;

    if !output.status.success() {
        return Ok(empty());
    }

    let raw = String::from_utf8_lossy(&output.stdout);
    let parsed: serde_json::Value = match serde_json::from_str(raw.trim()) {
        Ok(v) => v,
        Err(_) => return Ok(empty()),
    };

    Ok(PrInfo {
        url: parsed["url"].as_str().unwrap_or("").to_string(),
        is_draft: parsed["isDraft"].as_bool().unwrap_or(false),
        state: parsed["state"].as_str().unwrap_or("").to_string(),
        merged_at: parsed["mergedAt"].as_str().map(|s| s.to_string()),
    })
}
