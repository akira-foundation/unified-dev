use std::sync::Arc;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::db::models::{CreateOrganizationInput, OrganizationRecord, OrganizationSummary, UpdateOrganizationInput};
use crate::db::organization_repository::OrganizationRepository;
use crate::db::provider_repository::ProviderRepository;
use crate::error::{AppError, AppResult};

pub struct OrganizationService {
    organizations: Arc<dyn OrganizationRepository>,
    providers: Arc<dyn ProviderRepository>,
}

impl OrganizationService {
    pub fn new(
        organizations: Arc<dyn OrganizationRepository>,
        providers: Arc<dyn ProviderRepository>,
    ) -> Self {
        Self {
            organizations,
            providers,
        }
    }

    pub async fn create_organization(&self, input: CreateOrganizationInput) -> AppResult<OrganizationSummary> {
        let exists = self.providers.exists(&input.provider_id).await?;
        if !exists {
            return Err(AppError::Provider("provider not found".to_string()));
        }

        let id = Uuid::new_v4().to_string();
        let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();

        let organization = OrganizationRecord {
            id,
            name: input.name,
            provider_id: Some(input.provider_id),
            external_id: input.external_id,
            created_at,
        };

        self.organizations.create(&organization).await
    }

    pub async fn list_organizations(&self) -> AppResult<Vec<OrganizationSummary>> {
        self.organizations.list().await
    }

    pub async fn list_by_provider(&self, provider_id: &str) -> AppResult<Vec<OrganizationSummary>> {
        self.organizations.list_by_provider(provider_id).await
    }

    pub async fn update_organization(&self, input: UpdateOrganizationInput) -> AppResult<OrganizationSummary> {
        if let Some(ref provider_id) = input.provider_id {
            let exists = self.providers.exists(provider_id).await?;
            if !exists {
                return Err(AppError::Provider("provider not found".to_string()));
            }
        }
        self.organizations.update(&input).await
    }

    pub async fn delete_organization(&self, organization_id: &str) -> AppResult<()> {
        self.organizations.delete(organization_id).await
    }
}
