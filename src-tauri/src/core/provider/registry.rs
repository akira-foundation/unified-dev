use std::collections::HashMap;
use std::sync::Arc;

use crate::core::provider::traits::{ProviderDriverFactory, VcsProvider};
use crate::core::provider::types::{ProviderAuth, ProviderKind};
use crate::error::{AppError, AppResult};

#[derive(Clone, Default)]
pub struct ProviderFactory {
    factories: HashMap<ProviderKind, Arc<dyn ProviderDriverFactory>>,
}

impl ProviderFactory {
    pub fn new() -> Self {
        Self {
            factories: HashMap::new(),
        }
    }

    pub fn register(&mut self, factory: Arc<dyn ProviderDriverFactory>) {
        self.factories.insert(factory.kind(), factory);
    }

    pub async fn create(&self, provider_kind: &ProviderKind, auth: ProviderAuth) -> AppResult<Arc<dyn VcsProvider>> {
        let factory = self
            .factories
            .get(provider_kind)
            .cloned()
            .ok_or_else(|| AppError::Provider(format!("provider not found: {provider_kind}")))?;

        factory.create(auth).await
    }

    pub fn list(&self) -> Vec<ProviderKind> {
        self.factories.keys().cloned().collect()
    }
}
