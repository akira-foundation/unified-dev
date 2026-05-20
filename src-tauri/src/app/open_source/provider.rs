use sqlx::Row;

use crate::app::providers::credentials::credentials;
use crate::providers::drivers::github::client::GitHubDriver;
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

pub struct GitHubContext {
    pub provider_id: String,
    pub driver: GitHubDriver,
}

pub async fn find_github_driver(state: &AppState) -> Result<GitHubContext, String> {
    let row = sqlx::query(
        "SELECT id FROM providers WHERE kind = 'github'
         ORDER BY CASE auth_type WHEN 'pat' THEN 0 WHEN 'github_oauth' THEN 1 ELSE 2 END,
                  created_at DESC
         LIMIT 1",
    )
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?
    .ok_or_else(|| "github_not_connected".to_string())?;

    let provider_id: String = row.try_get("id").map_err(|e| e.to_string())?;

    let creds = credentials(state, &provider_id)
        .await
        .map_err(|_| "github_not_connected".to_string())?;

    if !matches!(creds.kind, ProviderKind::GitHub) {
        return Err("github_not_connected".to_string());
    }

    let token = match creds.auth {
        ProviderAuth::GitHubOAuth { access_token, .. } => access_token,
        ProviderAuth::PersonalAccessToken { token } => token,
        ProviderAuth::GitHubApp { oauth_access_token, .. } if !oauth_access_token.is_empty() => {
            oauth_access_token
        }
        ProviderAuth::GitHubApp { .. } => return Err("github_app_no_user_token".to_string()),
        _ => return Err("github_not_connected".to_string()),
    };

    let driver = GitHubDriver::new(token).map_err(|e| e.to_string())?;
    Ok(GitHubContext { provider_id, driver })
}
