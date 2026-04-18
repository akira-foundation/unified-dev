use reqwest::Client;
use serde::Deserialize;

use crate::app::support::error::{AppError, AppResult};

/// Resolves an environment variable by name, falling back to scanning common
/// shell init files. Tauri desktop apps do not inherit shell env vars set in
/// `.zshrc` / `.bashrc` etc. when launched from the Dock.
pub fn resolve_env_key(key: &str) -> Option<String> {
    if let Ok(val) = std::env::var(key) {
        if !val.is_empty() {
            return Some(val);
        }
    }

    let home = dirs::home_dir()?;
    let candidates = [
        home.join(".zshenv"),
        home.join(".zprofile"),
        home.join(".zshrc"),
        home.join(".bash_profile"),
        home.join(".bashrc"),
        home.join(".profile"),
    ];

    for path in &candidates {
        if let Ok(content) = std::fs::read_to_string(path) {
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with('#') {
                    continue;
                }
                let after_export = if let Some(s) = trimmed.strip_prefix("export ") {
                    s.trim_start()
                } else {
                    trimmed
                };
                if let Some(rest) = after_export.strip_prefix(key) {
                    if let Some(val_str) = rest.strip_prefix('=') {
                        let val = val_str.trim().trim_matches('"').trim_matches('\'');
                        if !val.is_empty() {
                            return Some(val.to_string());
                        }
                    }
                }
            }
        }
    }

    None
}

/// Reads the GitHub Copilot OAuth token from `~/.config/github-copilot/apps.json`.
pub fn read_copilot_oauth_token() -> Option<String> {
    let home = dirs::home_dir()?;
    let path = home.join(".config/github-copilot/apps.json");
    let content = std::fs::read_to_string(path).ok()?;
    let map: serde_json::Value = serde_json::from_str(&content).ok()?;
    let obj = map.as_object()?;
    let mut fallback: Option<String> = None;
    for (_, entry) in obj {
        if let Some(token) = entry.get("oauth_token").and_then(|t| t.as_str()) {
            if token.starts_with("ghu_") {
                return Some(token.to_string());
            }
            fallback = Some(token.to_string());
        }
    }
    fallback
}

/// Exchanges the Copilot OAuth token for a short-lived Copilot API token.
pub async fn exchange_copilot_token(oauth_token: &str) -> AppResult<String> {
    let client = Client::new();
    let resp = client
        .get("https://api.github.com/copilot_internal/v2/token")
        .header("Authorization", format!("token {oauth_token}"))
        .header("User-Agent", "unified-dev/1.0")
        .send()
        .await
        .map_err(AppError::Http)?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!(
            "Copilot token exchange failed {status}: {body}"
        )));
    }

    #[derive(Deserialize)]
    struct TokenResp {
        token: String,
    }

    let parsed: TokenResp = resp
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("Copilot token parse error: {e}")))?;

    Ok(parsed.token)
}

/// Reads the OpenAI Codex CLI access token from `~/.codex/auth.json`.
pub fn read_codex_access_token() -> Option<String> {
    let home = dirs::home_dir()?;
    let path = home.join(".codex/auth.json");
    let content = std::fs::read_to_string(path).ok()?;
    let val: serde_json::Value = serde_json::from_str(&content).ok()?;
    val.get("tokens")
        .and_then(|t| t.get("access_token"))
        .and_then(|t| t.as_str())
        .filter(|t| !t.is_empty())
        .map(|t| t.to_string())
}
