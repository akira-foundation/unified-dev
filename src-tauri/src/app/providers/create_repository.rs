use serde::Deserialize;
use tauri::State;

use crate::providers::dto::CreatedRepo;
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

pub async fn create_repository(
    state: State<'_, AppState>,
    input: CreateRepositoryInput,
) -> Result<CreatedRepo, String> {
    let credentials = crate::app::providers::credentials::credentials(&state, &input.provider_id)
        .await
        .map_err(|e| e.to_string())?;

    let kind = credentials.kind.clone();

    let auth = match (&kind, credentials.auth) {
        (ProviderKind::GitHub, ProviderAuth::GitHubApp { oauth_access_token, .. }) => {
            ProviderAuth::PersonalAccessToken { token: oauth_access_token }
        }
        (_, auth) => auth,
    };

    let provider = state
        .provider_factory
        .create(&kind, auth)
        .await
        .map_err(|e| e.to_string())?;

    provider
        .create_repository(
            input.organization_login.as_deref().filter(|s| !s.is_empty()),
            &input.name,
            input.description.as_deref(),
            input.private,
        )
        .await
        .map_err(|e| e.to_string())
}
