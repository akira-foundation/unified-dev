use std::sync::Arc;

use crate::config::service::OrganizationService;

pub struct AppState {
    pub organization_service: Arc<OrganizationService>,
}

impl AppState {
    pub fn new(organization_service: Arc<OrganizationService>) -> Self {
        Self {
            organization_service,
        }
    }
}
