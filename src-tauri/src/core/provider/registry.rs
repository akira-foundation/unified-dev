use std::collections::HashMap;
use std::sync::Arc;

use crate::core::provider::traits::{VcsProvider, VcsProviderFactory};
use crate::core::provider::types::{ProviderAuth, ProviderId};
use crate::error::{AppError, AppResult};

#[derive(Clone, Default)]
pub struct ProviderRegistry {
    factories: HashMap<ProviderId, Arc<dyn VcsProviderFactory>>,
}

impl ProviderRegistry {
    pub fn new() -> Self {
        Self {
            factories: HashMap::new(),
        }
    }

    pub fn register(&mut self, factory: Arc<dyn VcsProviderFactory>) {
        self.factories.insert(factory.id(), factory);
    }

    pub fn create(&self, provider_id: &ProviderId, auth: ProviderAuth) -> AppResult<Arc<dyn VcsProvider>> {
        let factory = self
            .factories
            .get(provider_id)
            .cloned()
            .ok_or_else(|| AppError::Provider(format!("provider not found: {provider_id}")))?;

        factory.create(auth)
    }

    pub fn list(&self) -> Vec<ProviderId> {
        self.factories.keys().cloned().collect()
    }
}
