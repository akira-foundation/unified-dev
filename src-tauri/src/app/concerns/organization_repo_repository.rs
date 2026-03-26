use async_trait::async_trait;

use crate::app::orgs::request::SelectRepoRequest;
use crate::database::models::{OrganizationRepoSummary, OrganizationRepoWithOrg};
use crate::app::support::error::AppResult;

#[async_trait]
pub trait OrganizationRepoRepository: Send + Sync {
    async fn list_selected_by_org(&self, organization_id: &str) -> AppResult<Vec<OrganizationRepoSummary>>;
    async fn list_all_selected(&self) -> AppResult<Vec<OrganizationRepoWithOrg>>;
    async fn replace_selected_repos(
        &self,
        organization_id: &str,
        repos: &[SelectRepoRequest],
        created_at: &str,
    ) -> AppResult<()>;
    async fn update_repo_stats(
        &self,
        organization_id: &str,
        repo_name: &str,
        default_branch: &str,
        visibility: &str,
        open_prs_count: i64,
    ) -> AppResult<()>;
}
