use std::sync::Arc;

use crate::core::provider::registry::ProviderFactory;
use crate::core::provider::types::{ProviderAuth, ProviderKind, ProviderRepo, VcsPullRequest};
use crate::error::AppResult;

#[derive(Clone)]
pub struct VcsSyncService {
    registry: Arc<ProviderFactory>,
}

impl VcsSyncService {
    pub fn new(registry: Arc<ProviderFactory>) -> Self {
        Self { registry }
    }

    pub async fn sync_repositories(
        &self,
        provider_kind: ProviderKind,
        auth: ProviderAuth,
    ) -> AppResult<Vec<ProviderRepo>> {
        let provider = self.registry.create(&provider_kind, auth)?;
        provider.list_repositories().await
    }

    pub async fn sync_pull_requests(
        &self,
        provider_kind: ProviderKind,
        owner: &str,
        repository: &str,
        auth: ProviderAuth,
    ) -> AppResult<Vec<VcsPullRequest>> {
        let provider = self.registry.create(&provider_kind, auth)?;
        provider.list_pull_requests(owner, repository).await
    }
}
