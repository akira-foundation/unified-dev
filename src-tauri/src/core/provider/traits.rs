use async_trait::async_trait;

use crate::core::provider::types::{ProviderAuth, ProviderId, VcsPullRequest, VcsRepository};
use crate::error::AppResult;

#[async_trait]
pub trait VcsProvider: Send + Sync {
    fn id(&self) -> ProviderId;
    fn name(&self) -> &str;

    async fn list_repositories(&self, organization: &str, auth: &ProviderAuth) -> AppResult<Vec<VcsRepository>>;

    async fn list_pull_requests(
        &self,
        owner: &str,
        repository: &str,
        auth: &ProviderAuth,
    ) -> AppResult<Vec<VcsPullRequest>>;
}
