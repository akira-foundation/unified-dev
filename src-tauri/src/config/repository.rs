use async_trait::async_trait;

use crate::config::models::{OrganizationConfig, OrganizationRepoSummary, OrganizationSummary, SelectedRepositoryInput};
use crate::error::AppResult;

#[async_trait]
pub trait OrganizationRepository: Send + Sync {
    async fn create(&self, organization: &OrganizationConfig, created_at: &str) -> AppResult<OrganizationSummary>;
    async fn delete(&self, organization_id: &str) -> AppResult<()>;
    async fn find_by_id(&self, organization_id: &str) -> AppResult<OrganizationConfig>;
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
        visibility: &str,
        is_selected: bool,
        auto_sync: bool,
        created_at: &str,
    ) -> AppResult<OrganizationRepoSummary>;
    async fn list_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>>;
    async fn list_selected_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>>;
    async fn list_sync_candidates(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>>;
    async fn replace_selected_repos(
        &self,
        organization_id: &str,
        repos: &[SelectedRepositoryInput],
        created_at: &str,
    ) -> AppResult<()>;
}
