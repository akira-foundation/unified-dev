use std::sync::Arc;

use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;

use crate::db::models::{OrganizationRepoSummary, SelectedRepositoryInput};
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
}
