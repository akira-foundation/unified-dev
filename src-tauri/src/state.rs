use std::sync::Arc;

use crate::core::provider::registry::ProviderFactory;
use crate::services::organization_repo_service::OrganizationRepoService;
use crate::services::organization_service::OrganizationService;
use crate::services::provider_service::ProviderService;

pub struct AppState {
    pub provider_service: Arc<ProviderService>,
    pub organization_service: Arc<OrganizationService>,
    pub organization_repo_service: Arc<OrganizationRepoService>,
    pub provider_factory: Arc<ProviderFactory>,
}

impl AppState {
    pub fn new(
        provider_service: Arc<ProviderService>,
        organization_service: Arc<OrganizationService>,
        organization_repo_service: Arc<OrganizationRepoService>,
        provider_factory: Arc<ProviderFactory>,
    ) -> Self {
        Self {
            provider_service,
            organization_service,
            organization_repo_service,
            provider_factory,
        }
    }
}
