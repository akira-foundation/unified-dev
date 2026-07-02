use std::path::Path;

pub fn parse_ahead_count(stdout: &str) -> bool {
    stdout.trim().parse::<u64>().map(|n| n > 0).unwrap_or(false)
}

pub async fn branch_ahead(workspace_path: String) -> Result<bool, String> {
    let workspace = Path::new(&workspace_path);
    if !workspace.exists() {
        return Ok(false);
    }

    let output = tokio::process::Command::new("git")
        .args(["rev-list", "--count", "HEAD", "--not", "--remotes"])
        .current_dir(workspace)
        .output()
        .await
        .map_err(|e| format!("Failed to run git rev-list: {e}"))?;

    if !output.status.success() {
        return Ok(false);
    }

    Ok(parse_ahead_count(&String::from_utf8_lossy(&output.stdout)))
}

#[cfg(test)]
mod tests {
    use super::parse_ahead_count;

    #[test]
    fn treats_positive_count_as_ahead() {
        assert!(parse_ahead_count("3\n"));
        assert!(parse_ahead_count("1"));
    }

    #[test]
    fn treats_zero_as_not_ahead() {
        assert!(!parse_ahead_count("0\n"));
    }

    #[test]
    fn treats_unparseable_output_as_not_ahead() {
        assert!(!parse_ahead_count(""));
        assert!(!parse_ahead_count("fatal: not a git repository"));
    }
}
