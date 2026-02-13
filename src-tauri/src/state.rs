use std::sync::Arc;

use crate::core::provider::registry::ProviderFactory;
use crate::services::organization_service::OrganizationService;
use crate::services::provider_service::ProviderService;

pub struct AppState {
    pub provider_service: Arc<ProviderService>,
    pub organization_service: Arc<OrganizationService>,
    pub provider_factory: Arc<ProviderFactory>,
}

impl AppState {
    pub fn new(
        provider_service: Arc<ProviderService>,
        organization_service: Arc<OrganizationService>,
        provider_factory: Arc<ProviderFactory>,
    ) -> Self {
        Self {
            provider_service,
            organization_service,
            provider_factory,
        }
    }
}
