use async_trait::async_trait;
use serde::Deserialize;

use crate::app::concerns::{ProviderDriverFactory, VcsProvider};
use crate::providers::dto::{CreatedRepo, ProviderOrg, ProviderRepo, VcsBranch, VcsCiCheck, VcsPrComment, VcsPrFile, VcsPullRequest, VcsIssue};
use crate::providers::enums::{ProviderAuth, ProviderKind, PrMergeStrategy, PrReviewEvent};
use crate::app::support::error::{AppError, AppResult};

use super::client::{GitHubDriver, GITHUB_API};

#[derive(Deserialize)]
struct InstallationRepositoriesResponse {
    repositories: Vec<InstallationRepository>,
}

#[derive(Deserialize, Clone)]
pub(super) struct InstallationRepository {
    pub(super) id: u64,
    pub(super) name: String,
    pub(super) owner: InstallationRepositoryOwner,
    pub(super) private: bool,
    pub(super) visibility: String,
    pub(super) default_branch: Option<String>,
    pub(super) fork: Option<bool>,
}

#[derive(Deserialize, Clone)]
pub(super) struct InstallationRepositoryOwner {
    pub(super) id: u64,
    pub(super) login: String,
    #[serde(rename = "type")]
    pub(super) kind: String,
}

pub(super) async fn list_installation_repositories(driver: &GitHubDriver) -> AppResult<Vec<InstallationRepository>> {
    let mut page = 1;
    let mut repositories = Vec::new();

    loop {
        let response = driver
            .client
            .get(format!("{GITHUB_API}/installation/repositories?per_page=100&page={page}"))
            .bearer_auth(&driver.token)
            .header("Accept", "application/vnd.github+json")
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(driver.api_error(status, body));
        }

        let chunk: InstallationRepositoriesResponse = response.json().await?;
        let count = chunk.repositories.len();
        repositories.extend(chunk.repositories);

        if count < 100 {
            break;
        }

        page += 1;
    }

    Ok(repositories)
}

pub struct GitHubFactory;

impl GitHubFactory {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl ProviderDriverFactory for GitHubFactory {
    fn kind(&self) -> ProviderKind {
        ProviderKind::GitHub
    }

    async fn create(&self, auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        let (token, user_token) = match auth {
            ProviderAuth::PersonalAccessToken { token } => (token, None),
            ProviderAuth::GitHubOAuth { access_token, .. } => (access_token, None),
            ProviderAuth::GitHubApp { installation_token, oauth_access_token, .. } => {
                (installation_token, Some(oauth_access_token))
            }
            _ => {
                return Err(AppError::Provider(
                    "unsupported auth type for GitHub provider".to_string(),
                ))
            }
        };

        Ok(std::sync::Arc::new(GitHubDriver::new(token)?.with_user_token(user_token)))
    }
}

#[async_trait]
impl VcsProvider for GitHubDriver {
    fn kind(&self) -> ProviderKind {
        ProviderKind::GitHub
    }

    async fn validate_auth(&self) -> AppResult<()> {
        let url = format!("{GITHUB_API}/user");
        let _: serde_json::Value = self.get_json(url).await?;
        Ok(())
    }

    async fn list_organizations(&self) -> AppResult<Vec<ProviderOrg>> {
        self.list_organizations_impl().await
    }

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
        self.list_repositories_impl().await
    }

    async fn list_organization_repositories(&self, organization: &str) -> AppResult<Vec<ProviderRepo>> {
        self.list_organization_repositories_impl(organization).await
    }

    async fn create_repository(&self, org_login: Option<&str>, name: &str, description: Option<&str>, private: bool) -> AppResult<CreatedRepo> {
        self.create_repository_impl(org_login, name, description, private).await
    }

    async fn delete_repository(&self, owner: &str, repo_name: &str) -> AppResult<()> {
        self.delete_repository_impl(owner, repo_name).await
    }

    async fn list_pull_requests(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<VcsPullRequest>> {
        self.list_pull_requests_impl(owner, repository).await
    }

    async fn get_pull_request_comments(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<Vec<VcsPrComment>> {
        self.get_pull_request_comments_impl(owner, repository, pr_number).await
    }

    async fn post_pull_request_comment(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        body: &str,
    ) -> AppResult<VcsPrComment> {
        self.post_pull_request_comment_impl(owner, repository, pr_number, body).await
    }

    async fn delete_pull_request_comment(
        &self,
        owner: &str,
        repository: &str,
        comment_id: &str,
    ) -> AppResult<()> {
        self.delete_pull_request_comment_impl(owner, repository, comment_id).await
    }

    async fn submit_pull_request_review(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        event: PrReviewEvent,
        body: Option<&str>,
    ) -> AppResult<()> {
        self.submit_pull_request_review_impl(owner, repository, pr_number, event, body).await
    }

    async fn merge_pull_request(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        strategy: PrMergeStrategy,
    ) -> AppResult<()> {
        self.merge_pull_request_impl(owner, repository, pr_number, strategy).await
    }

    async fn mark_pull_request_ready_for_review(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<()> {
        self.mark_pull_request_ready_for_review_impl(owner, repository, pr_number).await
    }

    async fn list_repository_labels(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<crate::providers::dto::VcsRepoLabel>> {
        self.list_repository_labels_impl(owner, repository).await
    }

    async fn set_pull_request_labels(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        labels: Vec<String>,
    ) -> AppResult<Vec<String>> {
        self.set_pull_request_labels_impl(owner, repository, pr_number, labels).await
    }

    async fn create_repository_label(
        &self,
        owner: &str,
        repository: &str,
        name: &str,
        color: Option<&str>,
        description: Option<&str>,
    ) -> AppResult<crate::providers::dto::VcsRepoLabel> {
        self.create_repository_label_impl(owner, repository, name, color, description).await
    }

    async fn update_pull_request_body(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        body: &str,
    ) -> AppResult<()> {
        self.update_pull_request_body_impl(owner, repository, pr_number, body).await
    }

    async fn list_pull_request_files(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<Vec<VcsPrFile>> {
        self.list_pull_request_files_impl(owner, repository, pr_number).await
    }

    async fn list_pr_checks(
        &self,
        owner: &str,
        repository: &str,
        sha: &str,
    ) -> AppResult<Vec<VcsCiCheck>> {
        self.list_pr_checks_impl(owner, repository, sha).await
    }

    async fn get_job_logs(
        &self,
        owner: &str,
        repository: &str,
        job_id: u64,
    ) -> AppResult<String> {
        self.get_job_logs_impl(owner, repository, job_id).await
    }

    async fn list_issues(
        &self,
        owner: &str,
        repository: &str,
        state: Option<&str>,
    ) -> AppResult<Vec<VcsIssue>> {
        self.list_issues_impl(owner, repository, state).await
    }

    async fn create_issue(
        &self,
        owner: &str,
        repository: &str,
        title: &str,
        body: Option<&str>,
        labels: Vec<String>,
        assignees: Vec<String>,
    ) -> AppResult<VcsIssue> {
        self.create_issue_impl(owner, repository, title, body, labels, assignees).await
    }

    async fn update_issue(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
        title: Option<&str>,
        body: Option<&str>,
        state: Option<&str>,
        labels: Option<Vec<String>>,
        assignees: Option<Vec<String>>,
    ) -> AppResult<VcsIssue> {
        self.update_issue_impl(owner, repository, issue_number, title, body, state, labels, assignees).await
    }

    async fn close_issue(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
        reason: Option<&str>,
    ) -> AppResult<()> {
        self.close_issue_impl(owner, repository, issue_number, reason).await
    }

    async fn delete_issue(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
    ) -> AppResult<()> {
        self.delete_issue_impl(owner, repository, issue_number).await
    }

    async fn list_branches(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<VcsBranch>> {
        self.list_branches_impl(owner, repository).await
    }

    async fn create_branch(
        &self,
        owner: &str,
        repository: &str,
        branch_name: &str,
        sha: &str,
    ) -> AppResult<VcsBranch> {
        self.create_branch_impl(owner, repository, branch_name, sha).await
    }

    async fn delete_branch(
        &self,
        owner: &str,
        repository: &str,
        branch_name: &str,
    ) -> AppResult<()> {
        self.delete_branch_impl(owner, repository, branch_name).await
    }
}
