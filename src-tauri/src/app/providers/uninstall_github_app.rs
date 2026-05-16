use tauri::State;

use crate::app::providers::credentials::credentials;
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

pub async fn uninstall_github_app(state: State<'_, AppState>, provider_id: String, target_login: String) -> Result<(), String> {
    let credentials = credentials(&state, &provider_id)
        .await
        .map_err(|error| error.to_string())?;

    if credentials.kind != ProviderKind::GitHub {
        return Err("provider is not GitHub".to_string());
    }

    let oauth_access_token = match credentials.auth {
        ProviderAuth::GitHubApp { oauth_access_token, .. } => oauth_access_token,
        _ => return Err("provider is not connected with GitHub App auth".to_string()),
    };

    let api_url = env!("AKIRA_BILLING_URL");

    let client = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .map_err(|e| e.to_string())?;

    let response = client
        .post(format!("{api_url}/github/uninstall-installation"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({
            "access_token": oauth_access_token,
            "target_login": target_login,
        }))
        .send()
        .await
        .map_err(|e| e.to_string())?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.map_err(|e| e.to_string())?;
        return Err(format!("GitHub App uninstall failed: {status} — {body}"));
    }

    Ok(())
}
