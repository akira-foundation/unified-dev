use std::sync::Arc;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::core::provider::types::{ProviderAuth, ProviderKind};
use crate::db::models::{
    CreateProviderInput, ProviderAuthPayload, ProviderRecord, ProviderSummary, UpdateProviderAuthInput,
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
        };

        self.providers.create(&provider).await
    }

    pub async fn list_providers(&self) -> AppResult<Vec<ProviderSummary>> {
        self.providers.list().await
    }

    pub async fn delete_provider(&self, provider_id: &str) -> AppResult<()> {
        let count = self.organizations.count_by_provider(provider_id).await?;
        if count > 0 {
            return Err(AppError::Provider(
                "cannot delete provider with organizations attached".to_string(),
            ));
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
        let auth = self.deserialize_auth(&provider.auth_type, &provider.auth_payload)?;
        let kind = ProviderKind::from_str(&provider.kind);

        Ok(ProviderCredentials { kind, auth })
    }

    fn serialize_auth(&self, auth: &ProviderAuth) -> AppResult<(String, String)> {
        match auth {
            ProviderAuth::PersonalAccessToken { token } => {
                let encrypted = self.cipher.encrypt(token)?;
                let payload = ProviderAuthPayload { token: encrypted };
                Ok(("pat".to_string(), serde_json::to_string(&payload)?))
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
            _ => Err(AppError::Provider("unknown auth type".to_string())),
        }
    }
}
