use std::path::Path;

use crate::app::repositories::types::PrInfo;

pub async fn check_pr(workspace_path: String) -> Result<PrInfo, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Ok(PrInfo { url: String::new(), is_draft: false });
    }

    let output = tokio::process::Command::new("gh")
        .args(["pr", "view", "--json", "url,isDraft", "--jq", "[.url, (.isDraft | tostring)] | join(\"|\")"])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run gh pr view: {e}"))?;

    if output.status.success() {
        let raw = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if let Some((url, draft_str)) = raw.split_once('|') {
            return Ok(PrInfo { url: url.to_string(), is_draft: draft_str.trim() == "true" });
        }
        Ok(PrInfo { url: raw, is_draft: false })
    } else {
        Ok(PrInfo { url: String::new(), is_draft: false })
    }
}
