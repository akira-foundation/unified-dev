use std::sync::Arc;

use crate::core::provider::registry::ProviderRegistry;
use crate::core::provider::types::{ProviderAuth, ProviderId, ProviderRepo, VcsPullRequest};
use crate::error::AppResult;

#[derive(Clone)]
pub struct VcsSyncService {
    registry: Arc<ProviderRegistry>,
}

impl VcsSyncService {
    pub fn new(registry: Arc<ProviderRegistry>) -> Self {
        Self { registry }
    }

    pub async fn sync_repositories(
        &self,
        provider_id: ProviderId,
        auth: ProviderAuth,
    ) -> AppResult<Vec<ProviderRepo>> {
        let provider = self.registry.create(&provider_id, auth)?;
        provider.list_repositories().await
    }

    pub async fn sync_pull_requests(
        &self,
        provider_id: ProviderId,
        owner: &str,
        repository: &str,
        auth: ProviderAuth,
    ) -> AppResult<Vec<VcsPullRequest>> {
        let provider = self.registry.create(&provider_id, auth)?;
        provider.list_pull_requests(owner, repository).await
    }
}
