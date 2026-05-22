use async_trait::async_trait;

use crate::app::concerns::{ProviderDriverFactory, VcsProvider};
use crate::providers::dto::{CreatedRepo, ProviderOrg, ProviderRepo, VcsBranch, VcsCiCheck, VcsPrComment, VcsPrFile, VcsPullRequest, VcsIssue};
use crate::providers::enums::{ProviderAuth, ProviderKind, PrMergeStrategy, PrReviewEvent};
use crate::app::support::error::{AppError, AppResult};

pub struct LinearDriver {
    #[allow(dead_code)]
    token: String,
}

impl LinearDriver {
    pub fn new(token: String) -> Self {
        Self { token }
    }
}

pub struct LinearFactory;

impl LinearFactory {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl ProviderDriverFactory for LinearFactory {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Other("linear".to_string())
    }

    async fn create(&self, auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        let token = match auth {
            ProviderAuth::PersonalAccessToken { token } => token,
            _ => {
                return Err(AppError::Provider(
                    "unsupported auth type for Linear provider".to_string(),
                ))
            }
        };

        Ok(std::sync::Arc::new(LinearDriver::new(token)))
    }
}

#[async_trait]
impl VcsProvider for LinearDriver {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Other("linear".to_string())
    }

    async fn validate_auth(&self) -> AppResult<()> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn list_organizations(&self) -> AppResult<Vec<ProviderOrg>> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn list_organization_repositories(&self, _organization: &str) -> AppResult<Vec<ProviderRepo>> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn create_repository(&self, _org_login: Option<&str>, _name: &str, _description: Option<&str>, _private: bool) -> AppResult<CreatedRepo> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn delete_repository(&self, _owner: &str, _repo_name: &str) -> AppResult<()> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn list_pull_requests(&self, _owner: &str, _repository: &str) -> AppResult<Vec<VcsPullRequest>> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn get_pull_request_comments(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
    ) -> AppResult<Vec<VcsPrComment>> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn post_pull_request_comment(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _body: &str,
    ) -> AppResult<VcsPrComment> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn delete_pull_request_comment(
        &self,
        _owner: &str,
        _repository: &str,
        _comment_id: &str,
    ) -> AppResult<()> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn submit_pull_request_review(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _event: PrReviewEvent,
        _body: Option<&str>,
    ) -> AppResult<()> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn merge_pull_request(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _strategy: PrMergeStrategy,
    ) -> AppResult<()> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn list_pull_request_files(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
    ) -> AppResult<Vec<VcsPrFile>> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn list_pr_checks(
        &self,
        _owner: &str,
        _repository: &str,
        _sha: &str,
    ) -> AppResult<Vec<VcsCiCheck>> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn get_job_logs(
        &self,
        _owner: &str,
        _repository: &str,
        _job_id: u64,
    ) -> AppResult<String> {
        Err(AppError::Provider("Linear: not yet implemented".to_string()))
    }

    async fn list_issues(
        &self,
        _owner: &str,
        _repository: &str,
        _state: Option<&str>,
    ) -> AppResult<Vec<VcsIssue>> {
        Err(AppError::Provider("Linear issues: not yet implemented".to_string()))
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
        Err(AppError::Provider("Linear issues: not yet implemented".to_string()))
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
        Err(AppError::Provider("Linear issues: not yet implemented".to_string()))
    }

    async fn close_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
        _reason: Option<&str>,
    ) -> AppResult<()> {
        Err(AppError::Provider("Linear issues: not yet implemented".to_string()))
    }

    async fn delete_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
    ) -> AppResult<()> {
        Err(AppError::Provider("Linear issues: not yet implemented".to_string()))
    }

    async fn list_branches(
        &self,
        _owner: &str,
        _repository: &str,
    ) -> AppResult<Vec<VcsBranch>> {
        Err(AppError::Provider("Branches not supported for Linear".to_string()))
    }

    async fn create_branch(
        &self,
        _owner: &str,
        _repository: &str,
        _branch_name: &str,
        _sha: &str,
    ) -> AppResult<VcsBranch> {
        Err(AppError::Provider("Create branch not supported for Linear".to_string()))
    }

    async fn delete_branch(
        &self,
        _owner: &str,
        _repository: &str,
        _branch_name: &str,
    ) -> AppResult<()> {
        Err(AppError::Provider("Delete branch not supported for Linear".to_string()))
    }
}
