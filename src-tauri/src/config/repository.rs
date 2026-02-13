use async_trait::async_trait;

use crate::config::models::{OrganizationConfig, OrganizationRepoSummary, OrganizationSummary};
use crate::error::AppResult;

#[async_trait]
pub trait OrganizationRepository: Send + Sync {
    async fn create(&self, organization: &OrganizationConfig, created_at: &str) -> AppResult<OrganizationSummary>;
    async fn delete(&self, organization_id: &str) -> AppResult<()>;
    async fn list(&self) -> AppResult<Vec<OrganizationSummary>>;
    async fn list_with_tokens(&self) -> AppResult<Vec<OrganizationConfig>>;
}

#[async_trait]
pub trait OrganizationRepoRepository: Send + Sync {
    async fn attach_repo(
        &self,
        organization_id: &str,
        owner: &str,
        repo_name: &str,
        auto_sync: bool,
    ) -> AppResult<OrganizationRepoSummary>;
    async fn list_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>>;
}
