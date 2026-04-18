use serde::Deserialize;
use tauri::State;

use crate::providers::drivers::github::client::{GitHubDriver, GITHUB_API};
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct DeleteRepositoryInput {
    pub provider_id: String,
    pub owner: String,
    pub repo_name: String,
}

pub async fn delete_repository(
    state: State<'_, AppState>,
    input: DeleteRepositoryInput,
) -> Result<(), String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &input.provider_id)
        .await
        .map_err(|e| e.to_string())?;

    if credentials.kind != ProviderKind::GitHub {
        return Err("Only GitHub providers are supported".to_string());
    }

    let token = match credentials.auth {
        ProviderAuth::GitHubApp { installation_token, .. } => installation_token,
        ProviderAuth::GitHubOAuth { access_token, .. } => access_token,
        ProviderAuth::PersonalAccessToken { token } => token,
        _ => return Err("Unsupported auth type for repository deletion".to_string()),
    };

    let driver = GitHubDriver::new(token).map_err(|e| e.to_string())?;
    let url = format!("{GITHUB_API}/repos/{}/{}", input.owner, input.repo_name);

    driver.delete(url).await.map_err(|e| {
        let msg = e.to_string();
        if msg.contains("403") {
            "Permission denied. Make sure your GitHub token has delete repository access.".to_string()
        } else if msg.contains("404") {
            "Repository not found on GitHub.".to_string()
        } else {
            msg
        }
    })
}
