use std::sync::Arc;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use crate::db::inputs::SelectedRepositoryInput;
use crate::db::models::{OrganizationRepoSummary, OrganizationRepoWithOrg};
use crate::db::organization_repo_repository::OrganizationRepoRepository;
use crate::error::AppResult;

pub struct OrganizationRepoService {
    repos: Arc<dyn OrganizationRepoRepository>,
}

impl OrganizationRepoService {
    pub fn new(repos: Arc<dyn OrganizationRepoRepository>) -> Self {
        Self { repos }
    }

    pub async fn save_selected_repositories(
        &self,
        organization_id: &str,
        repos: Vec<SelectedRepositoryInput>,
    ) -> AppResult<()> {
        let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
        self.repos
            .replace_selected_repos(organization_id, &repos, &created_at)
            .await
    }

    pub async fn list_selected_repositories(
        &self,
        organization_id: &str,
    ) -> AppResult<Vec<OrganizationRepoSummary>> {
        self.repos.list_selected_by_org(organization_id).await
    }

    pub async fn list_all_selected_repositories(&self) -> AppResult<Vec<OrganizationRepoWithOrg>> {
        self.repos.list_all_selected().await
    }

    pub async fn update_repo_stats(
        &self,
        organization_id: &str,
        repo_name: &str,
        default_branch: &str,
        visibility: &str,
        open_prs_count: i64,
    ) -> AppResult<()> {
        self.repos.update_repo_stats(organization_id, repo_name, default_branch, visibility, open_prs_count).await
    }
}
