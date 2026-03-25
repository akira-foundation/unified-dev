use async_trait::async_trait;

use crate::core::provider::traits::{ProviderDriverFactory, VcsProvider};
use crate::core::provider::types::{
    ProviderAuth, ProviderKind, ProviderOrg, ProviderOrgKind, ProviderRepo, PrMergeStrategy,
    PrReviewEvent, VcsBranch, VcsCiCheck, VcsPrComment, VcsPrFile, VcsPullRequest, VcsIssue,
};
use crate::error::{AppError, AppResult};

use super::client::{BitbucketDriver, BITBUCKET_API};
use super::types::{
    pr_to_pull_request, repo_to_provider, BitbucketPullRequest, BitbucketRepo, BitbucketUser,
    BitbucketWorkspace,
};

pub struct BitbucketFactory;

impl BitbucketFactory {
    pub fn new() -> Self {
        Self
    }
}

#[async_trait]
impl ProviderDriverFactory for BitbucketFactory {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Bitbucket
    }

    fn name(&self) -> &str {
        "Bitbucket"
    }

    async fn create(&self, auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        let (username, password) = match auth {
            ProviderAuth::AppPassword { username, password } => (username, password),
            _ => {
                return Err(AppError::Provider(
                    "unsupported auth type for Bitbucket provider".to_string(),
                ))
            }
        };

        Ok(std::sync::Arc::new(BitbucketDriver::new(username, password)?))
    }
}

#[async_trait]
impl VcsProvider for BitbucketDriver {
    fn kind(&self) -> ProviderKind {
        ProviderKind::Bitbucket
    }

    fn name(&self) -> &str {
        "Bitbucket"
    }

    async fn validate_auth(&self) -> AppResult<()> {
        let _: serde_json::Value = self.get_json(&format!("{BITBUCKET_API}/user")).await?;
        Ok(())
    }

    async fn list_organizations(&self) -> AppResult<Vec<ProviderOrg>> {
        let user: BitbucketUser = self.get_json(&format!("{BITBUCKET_API}/user")).await?;
        let workspaces: Vec<BitbucketWorkspace> = self
            .fetch_paginated(&format!("{BITBUCKET_API}/workspaces"))
            .await?;

        let personal_slug = user.username.clone().unwrap_or_else(|| user.account_id.clone());
        let mut results = Vec::with_capacity(workspaces.len() + 1);
        results.push(ProviderOrg {
            id: user.account_id,
            login: personal_slug.clone(),
            kind: ProviderOrgKind::Personal,
        });

        results.extend(workspaces.into_iter().filter_map(|ws| {
            if ws.slug == personal_slug {
                return None;
            }
            Some(ProviderOrg {
                id: ws.uuid.unwrap_or_else(|| ws.slug.clone()),
                login: ws.slug,
                kind: ProviderOrgKind::Organization,
            })
        }));

        Ok(results)
    }

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
        let url = format!("{BITBUCKET_API}/repositories/{username}?role=member", username = self.username);
        let repos: Vec<BitbucketRepo> = self.fetch_paginated(&url).await?;
        Ok(repos.into_iter().map(repo_to_provider).collect())
    }

    async fn list_organization_repositories(&self, organization: &str) -> AppResult<Vec<ProviderRepo>> {
        let url = format!("{BITBUCKET_API}/repositories/{organization}");
        let repos: Vec<BitbucketRepo> = self.fetch_paginated(&url).await?;
        Ok(repos.into_iter().map(repo_to_provider).collect())
    }

    async fn list_pull_requests(&self, owner: &str, repository: &str) -> AppResult<Vec<VcsPullRequest>> {
        let url = format!(
            "{BITBUCKET_API}/repositories/{owner}/{repository}/pullrequests?state=OPEN,MERGED,DECLINED"
        );
        let prs: Vec<BitbucketPullRequest> = self.fetch_paginated(&url).await?;
        Ok(prs.into_iter().map(pr_to_pull_request).collect())
    }

    async fn get_pull_request_comments(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
    ) -> AppResult<Vec<VcsPrComment>> {
        Err(AppError::Provider("PR comments not yet supported for Bitbucket".to_string()))
    }

    async fn post_pull_request_comment(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _body: &str,
    ) -> AppResult<VcsPrComment> {
        Err(AppError::Provider("PR comments not yet supported for Bitbucket".to_string()))
    }

    async fn submit_pull_request_review(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _event: PrReviewEvent,
        _body: Option<&str>,
    ) -> AppResult<()> {
        Err(AppError::Provider("PR reviews not yet supported for Bitbucket".to_string()))
    }

    async fn merge_pull_request(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
        _strategy: PrMergeStrategy,
    ) -> AppResult<()> {
        Err(AppError::Provider("PR merge not yet supported for Bitbucket".to_string()))
    }

    async fn list_pull_request_files(
        &self,
        _owner: &str,
        _repository: &str,
        _pr_number: u64,
    ) -> AppResult<Vec<VcsPrFile>> {
        Err(AppError::Provider("PR file diff not yet supported for Bitbucket".to_string()))
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
        Err(AppError::Provider("Issues not yet supported for Bitbucket".to_string()))
    }

    async fn get_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
    ) -> AppResult<VcsIssue> {
        Err(AppError::Provider("Issues not yet supported for Bitbucket".to_string()))
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
        Err(AppError::Provider("Issues not yet supported for Bitbucket".to_string()))
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
        Err(AppError::Provider("Issues not yet supported for Bitbucket".to_string()))
    }

    async fn close_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
        _reason: Option<&str>,
    ) -> AppResult<()> {
        Err(AppError::Provider("Issues not yet supported for Bitbucket".to_string()))
    }

    async fn delete_issue(
        &self,
        _owner: &str,
        _repository: &str,
        _issue_number: u64,
    ) -> AppResult<()> {
        Err(AppError::Provider("Issues not yet supported for Bitbucket".to_string()))
    }

    async fn list_branches(
        &self,
        _owner: &str,
        _repository: &str,
    ) -> AppResult<Vec<VcsBranch>> {
        Err(AppError::Provider("Branches not yet supported for Bitbucket".to_string()))
    }

    async fn create_branch(
        &self,
        _owner: &str,
        _repository: &str,
        _branch_name: &str,
        _sha: &str,
    ) -> AppResult<VcsBranch> {
        Err(AppError::Provider("Create branch not yet supported for Bitbucket".to_string()))
    }

    async fn delete_branch(
        &self,
        _owner: &str,
        _repository: &str,
        _branch_name: &str,
    ) -> AppResult<()> {
        Err(AppError::Provider("Delete branch not yet supported for Bitbucket".to_string()))
    }
}
