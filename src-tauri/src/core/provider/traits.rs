use async_trait::async_trait;

use crate::core::provider::types::{ProviderId, VcsPullRequest, VcsRepository};
use crate::error::AppResult;

#[async_trait]
pub trait VcsProvider: Send + Sync {
    fn id(&self) -> ProviderId;
    fn name(&self) -> &str;

    async fn list_repositories(&self, organization: &str, token: &str) -> AppResult<Vec<VcsRepository>>;

    async fn list_pull_requests(
        &self,
        owner: &str,
        repository: &str,
        token: &str,
    ) -> AppResult<Vec<VcsPullRequest>>;
}
