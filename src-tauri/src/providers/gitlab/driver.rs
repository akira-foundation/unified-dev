use async_trait::async_trait;

use crate::core::provider::traits::{ProviderDriverFactory, VcsProvider};
use crate::core::provider::types::{
    ProviderAuth, ProviderKind, ProviderOrg, ProviderOrgKind, ProviderRepo, PrMergeStrategy,
    PrReviewEvent, VcsBranch, VcsCiCheck, VcsPrComment, VcsPrFile, VcsPullRequest, VcsIssue,
};
use crate::error::{AppError, AppResult};

use super::client::{GitLabDriver, GITLAB_API};
use super::types::{
    mr_to_pull_request, project_to_provider, urlencoded, GitLabGroup, GitLabMergeRequest,
    GitLabProject, GitLabUser,
};

pub struct GitLabFactory;

impl GitLabFactory {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl ProviderDriverFactory for GitLabFactory {
    fn kind(&self) -> ProviderKind {
        ProviderKind::GitLab
    }

    fn name(&self) -> &str {
        "GitLab"
    }

    async fn create(&self, auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        let token = match auth {
            ProviderAuth::PersonalAccessToken { token } => token,
            _ => {
                return Err(AppError::Provider(
                    "unsupported auth type for GitLab provider".to_string(),
                ))
            }
        };

        Ok(std::sync::Arc::new(GitLabDriver::new(token)?))
    }
}

#[async_trait]
impl VcsProvider for GitLabDriver {
    fn kind(&self) -> ProviderKind {
        ProviderKind::GitLab
    }

    fn name(&self) -> &str {
        "GitLab"
    }

    async fn validate_auth(&self) -> AppResult<()> {
        let _: serde_json::Value = self.get_json(&format!("{GITLAB_API}/user")).await?;
        Ok(())
    }

    async fn list_organizations(&self) -> AppResult<Vec<ProviderOrg>> {
        let user: GitLabUser = self.get_json(&format!("{GITLAB_API}/user")).await?;
        let groups: Vec<GitLabGroup> = self
            .fetch_paginated(&format!("{GITLAB_API}/groups?min_access_level=10"))
            .await?;

        let mut results = Vec::with_capacity(groups.len() + 1);
        results.push(ProviderOrg {
            id: user.id.to_string(),
            login: user.username,
            kind: ProviderOrgKind::Personal,
        });

        results.extend(groups.into_iter().map(|g| ProviderOrg {
            id: g.id.to_string(),
            login: g.path,
            kind: ProviderOrgKind::Organization,
        }));

        Ok(results)
    }

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
        let projects: Vec<GitLabProject> = self
            .fetch_paginated(&format!("{GITLAB_API}/projects?membership=true&simple=false"))
            .await?;

        Ok(projects.into_iter().map(project_to_provider).collect())
    }

    async fn list_organization_repositories(&self, organization: &str) -> AppResult<Vec<ProviderRepo>> {
        let encoded = urlencoded(organization);
        let projects: Vec<GitLabProject> = self
            .fetch_paginated(&format!("{GITLAB_API}/groups/{encoded}/projects"))
            .await?;

        Ok(projects.into_iter().map(project_to_provider).collect())
    }

    async fn list_pull_requests(&self, owner: &str, repository: &str) -> AppResult<Vec<VcsPullRequest>> {
        let encoded = urlencoded(&format!("{owner}/{repository}"));
        let mrs: Vec<GitLabMergeRequest> = self
            .fetch_paginated(&format!("{GITLAB_API}/projects/{encoded}/merge_requests?state=all"))
            .await?;

        Ok(mrs.into_iter().map(mr_to_pull_request).collect())
    }

    async fn get_pull_request_comments(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
    ) -> AppResult<Vec<VcsPrComment>> {
        Err(AppError::Provider("PR comments not yet supported for GitLab".to_string()))
    }

    async fn post_pull_request_comment(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _body: &str,
    ) -> AppResult<VcsPrComment> {
        Err(AppError::Provider("PR comments not yet supported for GitLab".to_string()))
    }

    async fn submit_pull_request_review(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _event: PrReviewEvent,
        _body: Option<&str>,
    ) -> AppResult<()> {
        Err(AppError::Provider("PR reviews not yet supported for GitLab".to_string()))
    }

    async fn merge_pull_request(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _strategy: PrMergeStrategy,
    ) -> AppResult<()> {
        Err(AppError::Provider("PR merge not yet supported for GitLab".to_string()))
    }

    async fn list_pull_request_files(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
    ) -> AppResult<Vec<VcsPrFile>> {
        Err(AppError::Provider("PR file diff not yet supported for GitLab".to_string()))
    }

    async fn list_pr_checks(
        &self,
        _owner: &str,
        _repository: &str,
        _sha: &str,
    ) -> AppResult<Vec<VcsCiCheck>> {
        Ok(vec![])
    }

    async fn get_job_logs(
        &self,
        _owner: &str,
        _repository: &str,
        _job_id: u64,
    ) -> AppResult<String> {
        Ok(String::new())
    }

    async fn list_issues(
        &self,
        _owner: &str,
        _repository: &str,
        _state: Option<&str>,
    ) -> AppResult<Vec<VcsIssue>> {
        Err(AppError::Provider("Issues not yet supported for GitLab".to_string()))
    }

    async fn get_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
    ) -> AppResult<VcsIssue> {
        Err(AppError::Provider("Issues not yet supported for GitLab".to_string()))
    }

    async fn create_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _title: &str,
        _body: Option<&str>,
        _labels: Vec<String>,
        _assignees: Vec<String>,
    ) -> AppResult<VcsIssue> {
        Err(AppError::Provider("Issues not yet supported for GitLab".to_string()))
    }

    async fn update_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
        _title: Option<&str>,
        _body: Option<&str>,
        _state: Option<&str>,
        _labels: Option<Vec<String>>,
        _assignees: Option<Vec<String>>,
    ) -> AppResult<VcsIssue> {
        Err(AppError::Provider("Issues not yet supported for GitLab".to_string()))
    }

    async fn close_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
        _reason: Option<&str>,
    ) -> AppResult<()> {
        Err(AppError::Provider("Issues not yet supported for GitLab".to_string()))
    }

    async fn delete_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
    ) -> AppResult<()> {
        Err(AppError::Provider("Issues not yet supported for GitLab".to_string()))
    }

    async fn list_branches(
        &self,
        _owner: &str,
        _repository: &str,
    ) -> AppResult<Vec<VcsBranch>> {
        Err(AppError::Provider("Branches not yet supported for GitLab".to_string()))
    }

    async fn create_branch(
        &self,
        _owner: &str,
        _repository: &str,
        _branch_name: &str,
        _sha: &str,
    ) -> AppResult<VcsBranch> {
        Err(AppError::Provider("Create branch not yet supported for GitLab".to_string()))
    }

    async fn delete_branch(
        &self,
        _owner: &str,
        _repository: &str,
        _branch_name: &str,
    ) -> AppResult<()> {
        Err(AppError::Provider("Delete branch not yet supported for GitLab".to_string()))
    }
}
