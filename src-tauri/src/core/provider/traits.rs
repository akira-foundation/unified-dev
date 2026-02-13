use std::sync::Arc;

use async_trait::async_trait;

use crate::core::provider::types::{ProviderAuth, ProviderKind, ProviderRepo, VcsPullRequest};
use crate::error::AppResult;

pub trait ProviderDriverFactory: Send + Sync {
    fn kind(&self) -> ProviderKind;
    fn name(&self) -> &str;
    fn create(&self, auth: ProviderAuth) -> AppResult<Arc<dyn VcsProvider>>;
}

#[async_trait]
pub trait VcsProvider: Send + Sync {
    fn kind(&self) -> ProviderKind;
    fn name(&self) -> &str;

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>>;

    async fn list_pull_requests(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<VcsPullRequest>>;
}
