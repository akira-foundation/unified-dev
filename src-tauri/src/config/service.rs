use std::sync::Arc;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::config::models::{
    AppConfig, AttachRepoInput, CreateOrganizationInput, OrganizationConfig, OrganizationRepoSummary,
    OrganizationSummary, SelectedRepositoryInput,
};
use crate::core::provider::types::{ProviderAuth, ProviderId};
use crate::config::repository::{OrganizationRepoRepository, OrganizationRepository};
use crate::error::AppResult;
use crate::security::TokenCipher;

pub struct OrganizationService {
    organizations: Arc<dyn OrganizationRepository>,
    repos: Arc<dyn OrganizationRepoRepository>,
    cipher: TokenCipher,
}

pub struct OrganizationCredentials {
    pub provider_id: ProviderId,
    pub auth: ProviderAuth,
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
        let is_selected = input.is_selected.unwrap_or(true);
        let visibility = input.visibility.unwrap_or_else(|| "private".to_string());
        let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
        self.repos
            .attach_repo(
                &input.organization_id,
                &input.owner,
                &input.repo_name,
                &visibility,
                is_selected,
                auto_sync,
                &created_at,
            )
            .await
    }

    pub async fn list_repos(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        self.repos.list_by_org(organization_id).await
    }

    pub async fn list_selected_repos(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        self.repos.list_selected_by_org(organization_id).await
    }

    pub async fn list_sync_candidates(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>> {
        self.repos.list_sync_candidates(organization_id).await
    }

    pub async fn save_selected_repositories(
        &self,
        organization_id: &str,
        repos: Vec<SelectedRepositoryInput>,
    ) -> AppResult<()> {
        let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
        self.repos
            .replace_selected_repos(organization_id, &repos, &created_at)
            .await
    }

    pub async fn organization_credentials(&self, organization_id: &str) -> AppResult<OrganizationCredentials> {
        let organization = self.organizations.find_by_id(organization_id).await?;
        let auth = self.decrypt_auth(&organization.auth_json)?;
        let provider_id = ProviderId::from_str(&organization.provider_id);

        Ok(OrganizationCredentials { provider_id, auth })
    }

    pub async fn app_config(&self) -> AppResult<AppConfig> {
        let organizations = self.organizations.list_with_tokens().await?;
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

    fn decrypt_auth(&self, auth_json: &str) -> AppResult<ProviderAuth> {
        let decoded = self.cipher.decrypt(auth_json)?;
        Ok(serde_json::from_str(&decoded)?)
    }
}
