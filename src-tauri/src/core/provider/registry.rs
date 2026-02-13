use std::collections::HashMap;
use std::sync::Arc;

use crate::core::provider::traits::VcsProvider;
use crate::core::provider::types::ProviderId;
use crate::error::{AppError, AppResult};

#[derive(Clone, Default)]
pub struct ProviderRegistry {
    providers: HashMap<ProviderId, Arc<dyn VcsProvider>>,
}

impl ProviderRegistry {
    pub fn new() -> Self {
        Self {
            providers: HashMap::new(),
        }
    }

    pub fn register(&mut self, provider: Arc<dyn VcsProvider>) {
        self.providers.insert(provider.id(), provider);
    }

    pub fn get(&self, provider_id: &ProviderId) -> AppResult<Arc<dyn VcsProvider>> {
        self.providers
            .get(provider_id)
            .cloned()
            .ok_or_else(|| AppError::Provider(format!("provider not found: {provider_id}")))
    }

    pub fn list(&self) -> Vec<ProviderId> {
        self.providers.keys().cloned().collect()
    }
}
