use std::sync::Arc;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::core::provider::types::{ProviderAuth, ProviderKind};
use crate::db::models::{
    AppPasswordAuthPayload, CreateProviderInput, GitHubOAuthPayload, ProviderAuthPayload, ProviderRecord,
    ProviderSummary, UpdateProviderAuthInput,
};
use crate::db::organization_repository::OrganizationRepository;
use crate::db::provider_repository::ProviderRepository;
use crate::error::{AppError, AppResult};
use crate::security::TokenCipher;

pub struct ProviderCredentials {
    pub kind: ProviderKind,
    pub auth: ProviderAuth,
}

pub struct ProviderService {
    providers: Arc<dyn ProviderRepository>,
    organizations: Arc<dyn OrganizationRepository>,
    cipher: TokenCipher,
}

impl ProviderService {
    pub fn new(
        providers: Arc<dyn ProviderRepository>,
        organizations: Arc<dyn OrganizationRepository>,
        cipher: TokenCipher,
    ) -> Self {
        Self {
            providers,
            organizations,
            cipher,
        }
    }

    pub async fn create_provider(&self, input: CreateProviderInput) -> AppResult<ProviderSummary> {
        let id = Uuid::new_v4().to_string();
        let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
        let (auth_type, auth_payload) = self.serialize_auth(&input.auth)?;

        let provider = ProviderRecord {
            id,
            name: input.name,
            kind: input.kind,
            auth_type,
            auth_payload,
            created_at,
            account_login: input.account_login,
            account_type: input.account_type,
        };

        self.providers.create(&provider).await
    }

    pub async fn list_providers(&self) -> AppResult<Vec<ProviderSummary>> {
        self.providers.list().await
    }

    pub async fn delete_provider(&self, provider_id: &str, keep_organizations: bool) -> AppResult<()> {
        if !keep_organizations {
            let organizations = self.organizations.list_by_provider(provider_id).await?;
            for org in organizations {
                self.organizations.delete(&org.id).await?;
            }
        }

        self.providers.delete(provider_id).await
    }

    pub async fn update_provider_auth(&self, input: UpdateProviderAuthInput) -> AppResult<()> {
        let (auth_type, auth_payload) = self.serialize_auth(&input.auth)?;
        self.providers
            .update_auth(&input.provider_id, &auth_type, &auth_payload)
            .await
    }

    pub async fn credentials(&self, provider_id: &str) -> AppResult<ProviderCredentials> {
        let provider = self.providers.find_by_id(provider_id).await?;
        let mut auth = self.deserialize_auth(&provider.auth_type, &provider.auth_payload)?;
        let kind = ProviderKind::from_str(&provider.kind);

        if let ProviderAuth::GitHubOAuth { ref refresh_token, expires_at, .. } = auth {
            let should_refresh = match (refresh_token, expires_at) {
                (Some(_), Some(exp)) => {
                    let now = std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_secs() as i64;
                    now >= exp - 300 // refresh 5 min before expiry
                }
                _ => false,
            };

            if should_refresh {
                auth = self.refresh_github_token(provider_id, auth).await?;
            }
        }

        Ok(ProviderCredentials { kind, auth })
    }

    async fn refresh_github_token(&self, provider_id: &str, auth: ProviderAuth) -> AppResult<ProviderAuth> {
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
            expires_at: Some(now + 28800), // GitHub access tokens last 8h
        };

        let (auth_type, auth_payload) = self.serialize_auth(&new_auth)?;
        self.providers.update_auth(provider_id, &auth_type, &auth_payload).await?;

        Ok(new_auth)
    }

    fn serialize_auth(&self, auth: &ProviderAuth) -> AppResult<(String, String)> {
        match auth {
            ProviderAuth::PersonalAccessToken { token } => {
                let encrypted = self.cipher.encrypt(token)?;
                let payload = ProviderAuthPayload { token: encrypted };
                Ok(("pat".to_string(), serde_json::to_string(&payload)?))
            }
            ProviderAuth::GitHubOAuth { access_token, refresh_token, expires_at } => {
                let access_token_enc = self.cipher.encrypt(access_token)?;
                let refresh_token_enc = refresh_token
                    .as_deref()
                    .map(|t| self.cipher.encrypt(t))
                    .transpose()?;
                let payload = GitHubOAuthPayload {
                    access_token_enc,
                    refresh_token_enc,
                    expires_at: *expires_at,
                };
                Ok(("github_oauth".to_string(), serde_json::to_string(&payload)?))
            }
            ProviderAuth::AppPassword { username, password } => {
                let password_enc = self.cipher.encrypt(password)?;
                let payload = AppPasswordAuthPayload {
                    username: username.clone(),
                    password_enc,
                };
                Ok(("app_password".to_string(), serde_json::to_string(&payload)?))
            }
        }
    }

    fn deserialize_auth(&self, auth_type: &str, payload: &str) -> AppResult<ProviderAuth> {
        match auth_type {
            "pat" => {
                let decoded: ProviderAuthPayload = serde_json::from_str(payload)?;
                let token = self.cipher.decrypt(&decoded.token)?;
                Ok(ProviderAuth::PersonalAccessToken { token })
            }
            "github_oauth" => {
                let decoded: GitHubOAuthPayload = serde_json::from_str(payload)?;
                let access_token = self.cipher.decrypt(&decoded.access_token_enc)?;
                let refresh_token = decoded
                    .refresh_token_enc
                    .as_deref()
                    .map(|t| self.cipher.decrypt(t))
                    .transpose()?;
                Ok(ProviderAuth::GitHubOAuth { access_token, refresh_token, expires_at: decoded.expires_at })
            }
            "app_password" => {
                let decoded: AppPasswordAuthPayload = serde_json::from_str(payload)?;
                let password = self.cipher.decrypt(&decoded.password_enc)?;
                Ok(ProviderAuth::AppPassword {
                    username: decoded.username,
                    password,
                })
            }
            _ => Err(AppError::Provider("unknown auth type".to_string())),
        }
    }
}
