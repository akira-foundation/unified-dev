use crate::db::inputs::{AppPasswordAuthPayload, GitHubOAuthPayload, ProviderAuthPayload};
use crate::providers::types::{ProviderAuth, ProviderKind};
use crate::state::AppState;
use crate::support::error::{AppError, AppResult};

pub struct ProviderCredentials {
    pub kind: ProviderKind,
    pub auth: ProviderAuth,
}

pub async fn credentials(state: &AppState, provider_id: &str) -> AppResult<ProviderCredentials> {
    let provider = state.provider_repo.find_by_id(provider_id).await?;
    let mut auth = deserialize_auth(state, &provider.auth_type, &provider.auth_payload)?;
    let kind = ProviderKind::from_str(&provider.kind);

    if let ProviderAuth::GitHubOAuth { ref refresh_token, expires_at, .. } = auth {
        let should_refresh = match (refresh_token, expires_at) {
            (Some(_), Some(exp)) => {
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs() as i64;
                now >= exp - 300
            }
            _ => false,
        };

        if should_refresh {
            auth = refresh_github_token(state, provider_id, auth).await?;
        }
    }

    Ok(ProviderCredentials { kind, auth })
}

pub async fn refresh_github_token(state: &AppState, provider_id: &str, auth: ProviderAuth) -> AppResult<ProviderAuth> {
    let ProviderAuth::GitHubOAuth { refresh_token: Some(ref rt), .. } = auth else {
        return Ok(auth);
    };

    let api_url = env!("AKIRA_API_URL");

    #[derive(serde::Deserialize)]
    struct RefreshResponse {
        access_token: String,
        refresh_token: Option<String>,
    }

    let client = reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .map_err(|e| AppError::Provider(e.to_string()))?;

    let response = client
        .post(format!("{api_url}/github/refresh"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({ "refresh_token": rt }))
        .send()
        .await
        .map_err(|e| AppError::Provider(e.to_string()))?;

    if !response.status().is_success() {
        return Err(AppError::Provider("GitHub token refresh failed".to_string()));
    }

    let result: RefreshResponse = response
        .json()
        .await
        .map_err(|e| AppError::Provider(e.to_string()))?;

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    let new_auth = ProviderAuth::GitHubOAuth {
        access_token: result.access_token,
        refresh_token: result.refresh_token,
        expires_at: Some(now + 28800),
    };

    let (auth_type, auth_payload) = serialize_auth(state, &new_auth)?;
    state.provider_repo.update_auth(provider_id, &auth_type, &auth_payload).await?;

    Ok(new_auth)
}

pub fn serialize_auth(state: &AppState, auth: &ProviderAuth) -> AppResult<(String, String)> {
    match auth {
        ProviderAuth::PersonalAccessToken { token } => {
            let encrypted = state.token_cipher.encrypt(token)?;
            let payload = ProviderAuthPayload { token: encrypted };
            Ok(("pat".to_string(), serde_json::to_string(&payload)?))
        }
        ProviderAuth::GitHubOAuth { access_token, refresh_token, expires_at } => {
            let access_token_enc = state.token_cipher.encrypt(access_token)?;
            let refresh_token_enc = refresh_token
                .as_deref()
                .map(|t| state.token_cipher.encrypt(t))
                .transpose()?;
            let payload = GitHubOAuthPayload {
                access_token_enc,
                refresh_token_enc,
                expires_at: *expires_at,
            };
            Ok(("github_oauth".to_string(), serde_json::to_string(&payload)?))
        }
        ProviderAuth::AppPassword { username, password } => {
            let password_enc = state.token_cipher.encrypt(password)?;
            let payload = AppPasswordAuthPayload {
                username: username.clone(),
                password_enc,
            };
            Ok(("app_password".to_string(), serde_json::to_string(&payload)?))
        }
    }
}

pub fn deserialize_auth(state: &AppState, auth_type: &str, payload: &str) -> AppResult<ProviderAuth> {
    match auth_type {
        "pat" => {
            let decoded: ProviderAuthPayload = serde_json::from_str(payload)?;
            let token = state.token_cipher.decrypt(&decoded.token)?;
            Ok(ProviderAuth::PersonalAccessToken { token })
        }
        "github_oauth" => {
            let decoded: GitHubOAuthPayload = serde_json::from_str(payload)?;
            let access_token = state.token_cipher.decrypt(&decoded.access_token_enc)?;
            let refresh_token = decoded
                .refresh_token_enc
                .as_deref()
                .map(|t| state.token_cipher.decrypt(t))
                .transpose()?;
            Ok(ProviderAuth::GitHubOAuth { access_token, refresh_token, expires_at: decoded.expires_at })
        }
        "app_password" => {
            let decoded: AppPasswordAuthPayload = serde_json::from_str(payload)?;
            let password = state.token_cipher.decrypt(&decoded.password_enc)?;
            Ok(ProviderAuth::AppPassword {
                username: decoded.username,
                password,
            })
        }
        _ => Err(AppError::Provider("unknown auth type".to_string())),
    }
}
