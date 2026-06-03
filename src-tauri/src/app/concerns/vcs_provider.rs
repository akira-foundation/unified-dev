use async_trait::async_trait;

use crate::providers::dto::{CreatedRepo, ProviderOrg, ProviderRepo, VcsBranch, VcsCiCheck, VcsIssue, VcsPrComment, VcsPrFile, VcsPullRequest, VcsRepoLabel};
use crate::providers::enums::{PrMergeStrategy, PrReviewEvent, ProviderKind};
use crate::app::support::error::AppResult;

#[async_trait]
pub trait VcsProvider: Send + Sync {
    fn kind(&self) -> ProviderKind;

    async fn validate_auth(&self) -> AppResult<()>;
    async fn list_organizations(&self) -> AppResult<Vec<ProviderOrg>>;
    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>>;
    async fn list_organization_repositories(&self, organization: &str) -> AppResult<Vec<ProviderRepo>>;
    async fn create_repository(&self, org_login: Option<&str>, name: &str, description: Option<&str>, private: bool) -> AppResult<CreatedRepo>;
    async fn delete_repository(&self, owner: &str, repo_name: &str) -> AppResult<()>;
    async fn list_pull_requests(&self, owner: &str, repository: &str) -> AppResult<Vec<VcsPullRequest>>;
    async fn list_branches(&self, owner: &str, repository: &str) -> AppResult<Vec<VcsBranch>>;
    async fn create_branch(&self, owner: &str, repository: &str, branch_name: &str, sha: &str) -> AppResult<VcsBranch>;
    async fn delete_branch(&self, owner: &str, repository: &str, branch_name: &str) -> AppResult<()>;
    async fn get_pull_request_comments(&self, owner: &str, repository: &str, pr_number: u64) -> AppResult<Vec<VcsPrComment>>;
    async fn post_pull_request_comment(&self, owner: &str, repository: &str, pr_number: u64, body: &str) -> AppResult<VcsPrComment>;
    async fn delete_pull_request_comment(&self, owner: &str, repository: &str, comment_id: &str) -> AppResult<()>;
    async fn submit_pull_request_review(&self, owner: &str, repository: &str, pr_number: u64, event: PrReviewEvent, body: Option<&str>) -> AppResult<()>;
    async fn update_pull_request_body(&self, _owner: &str, _repository: &str, _pr_number: u64, _body: &str) -> AppResult<()> {
        Err(crate::app::support::error::AppError::Provider(
            "updating pull request description is not supported by this provider".into(),
        ))
    }
    async fn merge_pull_request(&self, owner: &str, repository: &str, pr_number: u64, strategy: PrMergeStrategy) -> AppResult<()>;
    async fn mark_pull_request_ready_for_review(&self, _owner: &str, _repository: &str, _pr_number: u64) -> AppResult<()> {
        Err(crate::app::support::error::AppError::Provider(
            "marking pull requests as ready for review is not supported by this provider".into(),
        ))
    }
    async fn close_pull_request(&self, _owner: &str, _repository: &str, _pr_number: u64, _comment: Option<&str>) -> AppResult<()> {
        Err(crate::app::support::error::AppError::Provider(
            "closing pull requests is not supported by this provider".into(),
        ))
    }
    async fn reopen_pull_request(&self, _owner: &str, _repository: &str, _pr_number: u64) -> AppResult<()> {
        Err(crate::app::support::error::AppError::Provider(
            "reopening pull requests is not supported by this provider".into(),
        ))
    }
    async fn list_repository_labels(&self, _owner: &str, _repository: &str) -> AppResult<Vec<VcsRepoLabel>> {
        Err(crate::app::support::error::AppError::Provider(
            "listing repository labels is not supported by this provider".into(),
        ))
    }
    async fn set_pull_request_labels(&self, _owner: &str, _repository: &str, _pr_number: u64, _labels: Vec<String>) -> AppResult<Vec<String>> {
        Err(crate::app::support::error::AppError::Provider(
            "editing pull request labels is not supported by this provider".into(),
        ))
    }
    async fn create_repository_label(&self, _owner: &str, _repository: &str, _name: &str, _color: Option<&str>, _description: Option<&str>) -> AppResult<VcsRepoLabel> {
        Err(crate::app::support::error::AppError::Provider(
            "creating repository labels is not supported by this provider".into(),
        ))
    }
    async fn list_pull_request_files(&self, owner: &str, repository: &str, pr_number: u64) -> AppResult<Vec<VcsPrFile>>;
    async fn list_pr_checks(&self, owner: &str, repository: &str, sha: &str) -> AppResult<Vec<VcsCiCheck>>;
    async fn get_job_logs(&self, owner: &str, repository: &str, job_id: u64) -> AppResult<String>;
    async fn list_issues(&self, owner: &str, repository: &str, state: Option<&str>) -> AppResult<Vec<VcsIssue>>;
    async fn create_issue(&self, owner: &str, repository: &str, title: &str, body: Option<&str>, labels: Vec<String>, assignees: Vec<String>) -> AppResult<VcsIssue>;
    async fn update_issue(&self, owner: &str, repository: &str, issue_number: u64, title: Option<&str>, body: Option<&str>, state: Option<&str>, labels: Option<Vec<String>>, assignees: Option<Vec<String>>) -> AppResult<VcsIssue>;
    async fn close_issue(&self, owner: &str, repository: &str, issue_number: u64, reason: Option<&str>) -> AppResult<()>;
    async fn delete_issue(&self, owner: &str, repository: &str, issue_number: u64) -> AppResult<()>;
}
