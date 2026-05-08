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
        "SELECT id FROM providers WHERE kind = 'github' ORDER BY created_at ASC LIMIT 1",
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
        ProviderAuth::GitHubApp { oauth_access_token, .. } => oauth_access_token,
        _ => return Err("github_not_connected".to_string()),
    };

    let driver = GitHubDriver::new(token).map_err(|e| e.to_string())?;
    Ok(GitHubContext { provider_id, driver })
}
