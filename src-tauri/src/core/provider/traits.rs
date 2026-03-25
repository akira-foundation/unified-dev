use std::sync::Arc;

use async_trait::async_trait;

use crate::core::provider::types::{ProviderAuth, ProviderKind, ProviderOrg, ProviderRepo, VcsCiCheck, VcsPrComment, VcsPrFile, VcsPullRequest, PrReviewEvent, PrMergeStrategy, VcsIssue};
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

    async fn get_pull_request_comments(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<Vec<VcsPrComment>>;

    async fn post_pull_request_comment(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        body: &str,
    ) -> AppResult<VcsPrComment>;

    async fn submit_pull_request_review(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        event: PrReviewEvent,
        body: Option<&str>,
    ) -> AppResult<()>;

    async fn merge_pull_request(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        strategy: PrMergeStrategy,
    ) -> AppResult<()>;

    async fn list_pull_request_files(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<Vec<VcsPrFile>>;

    async fn list_pr_checks(
        &self,
        owner: &str,
        repository: &str,
        sha: &str,
    ) -> AppResult<Vec<VcsCiCheck>>;

    async fn get_job_logs(
        &self,
        owner: &str,
        repository: &str,
        job_id: u64,
    ) -> AppResult<String>;

    // Issue tracker methods

    async fn list_issues(
        &self,
        owner: &str,
        repository: &str,
        state: Option<&str>,
    ) -> AppResult<Vec<VcsIssue>>;

    async fn get_issue(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
    ) -> AppResult<VcsIssue>;

    async fn create_issue(
        &self,
        owner: &str,
        repository: &str,
        title: &str,
        body: Option<&str>,
        labels: Vec<String>,
        assignees: Vec<String>,
    ) -> AppResult<VcsIssue>;

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
    ) -> AppResult<VcsIssue>;

    async fn close_issue(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
        reason: Option<&str>,
    ) -> AppResult<()>;
}
