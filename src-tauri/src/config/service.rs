use std::sync::Arc;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::config::models::{
    AppConfig, AttachRepoInput, CreateOrganizationInput, OrganizationConfig, OrganizationRepoSummary,
    OrganizationSummary,
};
use crate::core::provider::types::ProviderAuth;
use crate::config::repository::{OrganizationRepoRepository, OrganizationRepository};
use crate::error::AppResult;
use crate::security::TokenCipher;

pub struct OrganizationService {
    organizations: Arc<dyn OrganizationRepository>,
    repos: Arc<dyn OrganizationRepoRepository>,
    cipher: TokenCipher,
}

impl OrganizationService {
    pub fn new(
        organizations: Arc<dyn OrganizationRepository>,
        repos: Arc<dyn OrganizationRepoRepository>,
        cipher: TokenCipher,
    ) -> Self {
        Self {
            organizations,
            repos,
            cipher,
        }
    }

    pub async fn create_organization(&self, input: CreateOrganizationInput) -> AppResult<OrganizationSummary> {
        let id = Uuid::new_v4().to_string();
        let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
        let auth_json = self.encrypt_auth(input.auth)?;

        let organization = OrganizationConfig {
            id,
            name: input.name,
            provider_id: input.provider_id,
            auth_json,
        };

        self.organizations.create(&organization, &created_at).await
    }

    pub async fn delete_organization(&self, organization_id: &str) -> AppResult<()> {
        self.organizations.delete(organization_id).await
    }

    pub async fn list_organizations(&self) -> AppResult<Vec<OrganizationSummary>> {
        self.organizations.list().await
    }

    pub async fn attach_repo(&self, input: AttachRepoInput) -> AppResult<OrganizationRepoSummary> {
        let auto_sync = input.auto_sync.unwrap_or(true);
        self.repos
            .attach_repo(&input.organization_id, &input.owner, &input.repo_name, auto_sync)
            .await
    }

    pub async fn list_repos(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        self.repos.list_by_org(organization_id).await
    }

    pub async fn app_config(&self) -> AppResult<AppConfig> {
        let mut organizations = self.organizations.list_with_tokens().await?;
        Ok(AppConfig { organizations })
    }

    fn encrypt_auth(&self, auth: ProviderAuth) -> AppResult<String> {
        let encrypted_auth = match auth {
            ProviderAuth::Pat { token } => ProviderAuth::Pat {
                token: self.cipher.encrypt(&token)?,
            },
        };

        Ok(serde_json::to_string(&encrypted_auth)?)
    }
}
