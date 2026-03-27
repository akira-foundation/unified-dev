use serde::{Deserialize, Serialize};
use tauri::State;

use crate::app::providers::credentials::credentials;
use crate::providers::enums::{ProviderAuth, ProviderKind};
use crate::state::AppState;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RateLimitResource {
    pub limit: u32,
    pub used: u32,
    pub remaining: u32,
    pub reset: u64,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct RateLimitDto {
    pub provider_id: String,
    pub provider_name: String,
    pub core: RateLimitResource,
    pub search: RateLimitResource,
    pub graphql: RateLimitResource,
}

#[derive(Deserialize)]
struct GitHubRateLimitResponse {
    resources: GitHubRateLimitResources,
}

#[derive(Deserialize)]
struct GitHubRateLimitResources {
    core: GitHubRateLimitResource,
    search: GitHubRateLimitResource,
    graphql: GitHubRateLimitResource,
}

#[derive(Deserialize)]
struct GitHubRateLimitResource {
    limit: u32,
    used: u32,
    remaining: u32,
    reset: u64,
}

pub async fn get_rate_limit(state: State<'_, AppState>) -> Result<Vec<RateLimitDto>, String> {
    let providers = sqlx::query_as::<_, crate::database::records::ProviderRecord>(
        "SELECT id, name, kind, auth_type, auth_payload, created_at, account_login, account_type FROM providers WHERE kind = 'github'",
    )
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let client = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .map_err(|e| e.to_string())?;

    let mut results = Vec::new();

    for provider in providers {
        let creds = credentials(&state, &provider.id)
            .await
            .map_err(|e| e.to_string())?;

        if creds.kind != ProviderKind::GitHub {
            continue;
        }

        let token = match creds.auth {
            ProviderAuth::PersonalAccessToken { token } => token,
            ProviderAuth::GitHubOAuth { access_token, .. } => access_token,
            _ => continue,
        };

        let response = client
            .get("https://api.github.com/rate_limit")
            .bearer_auth(&token)
            .header("Accept", "application/vnd.github+json")
            .send()
            .await
            .map_err(|e| e.to_string())?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(format!("GitHub API error: {status} {body}"));
        }

        let data: GitHubRateLimitResponse = response.json().await.map_err(|e| e.to_string())?;

        results.push(RateLimitDto {
            provider_id: provider.id,
            provider_name: provider.name,
            core: RateLimitResource {
                limit: data.resources.core.limit,
                used: data.resources.core.used,
                remaining: data.resources.core.remaining,
                reset: data.resources.core.reset,
            },
            search: RateLimitResource {
                limit: data.resources.search.limit,
                used: data.resources.search.used,
                remaining: data.resources.search.remaining,
                reset: data.resources.search.reset,
            },
            graphql: RateLimitResource {
                limit: data.resources.graphql.limit,
                used: data.resources.graphql.used,
                remaining: data.resources.graphql.remaining,
                reset: data.resources.graphql.reset,
            },
        });
    }

    Ok(results)
}
