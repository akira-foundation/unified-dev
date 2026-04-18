use serde::{Deserialize, Serialize};
use tauri::State;

use crate::providers::drivers::github::client::{GitHubDriver, GITHUB_API};
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct CreateRepositoryInput {
    pub provider_id: String,
    pub organization_login: Option<String>,
    pub name: String,
    pub description: Option<String>,
    pub private: bool,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct CreatedRepository {
    pub id: i64,
    pub name: String,
    pub full_name: String,
    pub html_url: String,
    pub private: bool,
    pub description: Option<String>,
}

#[derive(Serialize)]
struct CreateRepoPayload {
    name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    description: Option<String>,
    private: bool,
    auto_init: bool,
}

pub async fn create_repository(
    state: State<'_, AppState>,
    input: CreateRepositoryInput,
) -> Result<CreatedRepository, String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &input.provider_id)
        .await
        .map_err(|e| e.to_string())?;

    if credentials.kind != ProviderKind::GitHub {
        return Err("Only GitHub providers are supported".to_string());
    }

    let token = match credentials.auth {
        ProviderAuth::GitHubApp { oauth_access_token, .. } => oauth_access_token,
        ProviderAuth::GitHubOAuth { access_token, .. } => access_token,
        ProviderAuth::PersonalAccessToken { token } => token,
        _ => return Err("Unsupported auth type for repository creation".to_string()),
    };

    let driver = GitHubDriver::new(token).map_err(|e| e.to_string())?;

    let payload = CreateRepoPayload {
        name: input.name,
        description: input.description,
        private: input.private,
        auto_init: true,
    };

    let url = match input.organization_login {
        Some(ref login) if !login.is_empty() => {
            format!("{GITHUB_API}/orgs/{login}/repos")
        }
        _ => format!("{GITHUB_API}/user/repos"),
    };

    let result = driver.post_json::<_, CreatedRepository>(url, &payload).await;

    match result {
        Ok(repo) => Ok(repo),
        Err(e) => {
            let msg = e.to_string();
            if msg.contains("403") && msg.contains("Resource not accessible by integration") {
                Err("The GitHub App does not have permission to create repositories. If you recently added Administration permissions to the app, each organization must approve the updated permissions — open the GitHub App settings page and accept the new permission request.".to_string())
            } else if msg.contains("422") {
                Err("Repository name is already taken or invalid. Please choose a different name.".to_string())
            } else {
                Err(msg)
            }
        }
    }
}
