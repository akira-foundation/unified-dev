use std::sync::Arc;

use crate::config::service::OrganizationService;
use crate::core::provider::registry::ProviderRegistry;

pub struct AppState {
    pub organization_service: Arc<OrganizationService>,
    pub provider_registry: Arc<ProviderRegistry>,
}

impl AppState {
    pub fn new(organization_service: Arc<OrganizationService>, provider_registry: Arc<ProviderRegistry>) -> Self {
        Self {
            organization_service,
            provider_registry,
        }
    }
}
