use std::sync::Arc;

use async_trait::async_trait;

use crate::core::provider::types::{ProviderAuth, ProviderKind, ProviderOrg, ProviderRepo, VcsPullRequest};
use crate::error::AppResult;

#[async_trait]
pub trait ProviderDriverFactory: Send + Sync {
    fn kind(&self) -> ProviderKind;
    fn name(&self) -> &str;
    async fn create(&self, auth: ProviderAuth) -> AppResult<Arc<dyn VcsProvider>>;
}

#[async_trait]
pub trait VcsProvider: Send + Sync {
    fn kind(&self) -> ProviderKind;
    fn name(&self) -> &str;

    async fn validate_auth(&self) -> AppResult<()>;

    async fn list_organizations(&self) -> AppResult<Vec<ProviderOrg>>;

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>>;

    async fn list_organization_repositories(&self, organization: &str) -> AppResult<Vec<ProviderRepo>>;

    async fn list_pull_requests(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<VcsPullRequest>>;
}
