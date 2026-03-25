use async_trait::async_trait;
use futures_util::future::join_all;
use serde::Deserialize;

use crate::core::provider::traits::{ProviderDriverFactory, VcsProvider};
use crate::core::provider::types::{
    ProviderAuth, ProviderKind, ProviderOrg, ProviderOrgKind, ProviderRepo, PrMergeStrategy,
    PrReviewEvent, PullRequestState, VcsBranch, VcsCiCheck, VcsCiCheckStep, VcsPrComment,
    VcsPrFile, VcsPullRequest, VcsIssue,
};
use crate::error::{AppError, AppResult};

use super::client::{GitHubDriver, GITHUB_API};
use super::types::{
    github_issue_to_vcs, repo_to_provider, GitHubBranch, GitHubCheckRunsResponse,
    GitHubIssue, GitHubIssueComment, GitHubJobResponse, GitHubOrg, GitHubPrFile,
    GitHubPullRequest, GitHubRef, GitHubUser,
};

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

    fn name(&self) -> &str {
        "GitHub"
    }

    async fn create(&self, auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        let token = match auth {
            ProviderAuth::PersonalAccessToken { token } => token,
            ProviderAuth::GitHubOAuth { access_token, .. } => access_token,
            _ => {
                return Err(AppError::Provider(
                    "unsupported auth type for GitHub provider".to_string(),
                ))
            }
        };

        Ok(std::sync::Arc::new(GitHubDriver::new(token)?))
    }
}

#[async_trait]
impl VcsProvider for GitHubDriver {
    fn kind(&self) -> ProviderKind {
        ProviderKind::GitHub
    }

    fn name(&self) -> &str {
        "GitHub"
    }

    async fn validate_auth(&self) -> AppResult<()> {
        let url = format!("{GITHUB_API}/user");
        let _: serde_json::Value = self.get_json(url).await?;
        Ok(())
    }

    async fn list_organizations(&self) -> AppResult<Vec<ProviderOrg>> {
        let user: GitHubUser = self.get_json(format!("{GITHUB_API}/user")).await?;
        let orgs: Vec<GitHubOrg> = self.fetch_paginated(format!("{GITHUB_API}/user/orgs")).await?;

        let mut results = Vec::with_capacity(orgs.len() + 1);
        results.push(ProviderOrg {
            id: user.id.to_string(),
            login: user.login,
            kind: ProviderOrgKind::Personal,
        });

        results.extend(orgs.into_iter().map(|org| ProviderOrg {
            id: org.id.to_string(),
            login: org.login,
            kind: ProviderOrgKind::Organization,
        }));

        Ok(results)
    }

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
        let url = format!("{GITHUB_API}/user/repos?type=all");
        let repositories: Vec<super::types::GitHubRepo> = self.fetch_paginated(url).await?;

        Ok(repositories
            .into_iter()
            .map(repo_to_provider)
            .collect())
    }

    async fn list_organization_repositories(&self, organization: &str) -> AppResult<Vec<ProviderRepo>> {
        let url = format!("{GITHUB_API}/orgs/{organization}/repos?type=all");
        let repositories: Vec<super::types::GitHubRepo> = self.fetch_paginated(url).await?;

        Ok(repositories
            .into_iter()
            .map(repo_to_provider)
            .collect())
    }

    async fn list_pull_requests(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<VcsPullRequest>> {
        let url = format!(
            "{GITHUB_API}/repos/{owner}/{repository}/pulls?state=all"
        );
        let pulls: Vec<GitHubPullRequest> = self.fetch_paginated(url).await?;

        let ci_futures: Vec<_> = pulls
            .iter()
            .map(|pr| {
                let sha = pr.head.sha.clone();
                let check_url = format!(
                    "{GITHUB_API}/repos/{owner}/{repository}/commits/{sha}/check-runs?per_page=100"
                );
                async move {
                    let resp = self
                        .get_json::<GitHubCheckRunsResponse>(check_url)
                        .await
                        .ok()?;

                    if resp.total_count == 0 {
                        return None;
                    }

                    let has_pending = resp.check_runs.iter().any(|r| {
                        matches!(r.status.as_str(), "in_progress" | "queued" | "waiting")
                    });
                    if has_pending {
                        return Some("pending".to_string());
                    }

                    let has_failure = resp.check_runs.iter().any(|r| {
                        r.conclusion
                            .as_deref()
                            .map(|c| matches!(c, "failure" | "timed_out" | "cancelled"))
                            .unwrap_or(false)
                    });
                    if has_failure {
                        return Some("failure".to_string());
                    }

                    Some("success".to_string())
                }
            })
            .collect();

        let ci_statuses = join_all(ci_futures).await;

        Ok(pulls
            .into_iter()
            .zip(ci_statuses)
            .map(|(pr, ci_status)| VcsPullRequest {
                id: pr.id.to_string(),
                number: pr.number,
                title: pr.title,
                state: match pr.state.as_str() {
                    "open" => PullRequestState::Open,
                    _ => PullRequestState::Closed,
                },
                url: pr.html_url,
                head: pr.head.reference,
                base: pr.base.reference,
                head_sha: pr.head.sha,
                updated_at: pr.updated_at,
                is_draft: pr.draft.unwrap_or(false),
                merged_at: pr.merged_at,
                body: pr.body,
                author: pr.user.map(|u| u.login),
                labels: pr.labels.unwrap_or_default().into_iter().map(|l| l.name).collect(),
                reviewers: pr.requested_reviewers.unwrap_or_default().into_iter().map(|u| u.login).collect(),
                ci_status,
            })
            .collect())
    }

    async fn get_pull_request_comments(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<Vec<VcsPrComment>> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues/{pr_number}/comments");
        let comments: Vec<GitHubIssueComment> = self.fetch_paginated(url).await?;

        Ok(comments
            .into_iter()
            .map(|c| VcsPrComment {
                id: c.id.to_string(),
                author: c.user.map(|u| u.login).unwrap_or_else(|| "unknown".to_string()),
                body: c.body.unwrap_or_default(),
                created_at: c.created_at,
            })
            .collect())
    }

    async fn post_pull_request_comment(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        body: &str,
    ) -> AppResult<VcsPrComment> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues/{pr_number}/comments");
        let payload = serde_json::json!({ "body": body });
        let comment: GitHubIssueComment = self.post_json(url, &payload).await?;

        Ok(VcsPrComment {
            id: comment.id.to_string(),
            author: comment.user.map(|u| u.login).unwrap_or_else(|| "unknown".to_string()),
            body: comment.body.unwrap_or_default(),
            created_at: comment.created_at,
        })
    }

    async fn submit_pull_request_review(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        event: PrReviewEvent,
        body: Option<&str>,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/pulls/{pr_number}/reviews");
        let event_str = match event {
            PrReviewEvent::Approve => "APPROVE",
            PrReviewEvent::RequestChanges => "REQUEST_CHANGES",
            PrReviewEvent::Comment => "COMMENT",
        };
        let mut payload = serde_json::json!({ "event": event_str });
        if let Some(b) = body {
            payload["body"] = serde_json::Value::String(b.to_string());
        }
        let _: serde_json::Value = self.post_json(url, &payload).await?;
        Ok(())
    }

    async fn merge_pull_request(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        strategy: PrMergeStrategy,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/pulls/{pr_number}/merge");
        let merge_method = match strategy {
            PrMergeStrategy::Merge => "merge",
            PrMergeStrategy::Squash => "squash",
            PrMergeStrategy::Rebase => "rebase",
        };
        let payload = serde_json::json!({ "merge_method": merge_method });
        self.put_json(url, &payload).await
    }

    async fn list_pull_request_files(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<Vec<VcsPrFile>> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/pulls/{pr_number}/files");
        let files: Vec<GitHubPrFile> = self.fetch_paginated(url).await?;

        Ok(files
            .into_iter()
            .map(|f| VcsPrFile {
                filename: f.filename,
                status: f.status,
                additions: f.additions,
                deletions: f.deletions,
                patch: f.patch,
            })
            .collect())
    }

    async fn list_pr_checks(
        &self,
        owner: &str,
        repository: &str,
        sha: &str,
    ) -> AppResult<Vec<VcsCiCheck>> {
        let url = format!(
            "{GITHUB_API}/repos/{owner}/{repository}/commits/{sha}/check-runs?per_page=100"
        );
        let resp: GitHubCheckRunsResponse = self.get_json(url).await?;

        let step_futures = resp.check_runs.iter().map(|r| {
            let job_url = format!("{GITHUB_API}/repos/{owner}/{repository}/actions/jobs/{}", r.id);
            self.get_json::<GitHubJobResponse>(job_url)
        });
        let step_results = join_all(step_futures).await;

        Ok(resp
            .check_runs
            .into_iter()
            .zip(step_results.into_iter())
            .map(|(r, steps_result)| {
                let steps = steps_result
                    .ok()
                    .and_then(|j| j.steps)
                    .unwrap_or_default()
                    .into_iter()
                    .map(|s| VcsCiCheckStep {
                        number: s.number,
                        name: s.name,
                        status: s.status,
                        conclusion: s.conclusion,
                        started_at: s.started_at,
                        completed_at: s.completed_at,
                    })
                    .collect();
                VcsCiCheck {
                    id: r.id,
                    name: r.name,
                    status: r.status,
                    conclusion: r.conclusion,
                    started_at: r.started_at,
                    completed_at: r.completed_at,
                    steps,
                }
            })
            .collect())
    }

    async fn get_job_logs(
        &self,
        owner: &str,
        repository: &str,
        job_id: u64,
    ) -> AppResult<String> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/actions/jobs/{job_id}/logs");
        let blob_url = self.get_redirect_url(url).await?;
        // Fetch the presigned S3 URL without auth headers (S3 rejects Bearer token on presigned URLs)
        let response = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?
            .get(blob_url)
            .send()
            .await?;
        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("Logs fetch error: {status} {body}")));
        }
        Ok(response.text().await?)
    }

    async fn list_issues(
        &self,
        owner: &str,
        repository: &str,
        state: Option<&str>,
    ) -> AppResult<Vec<VcsIssue>> {
        let state_param = state.unwrap_or("open");
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues?state={state_param}&filter=all");
        let issues: Vec<GitHubIssue> = self.fetch_paginated(url).await?;

        // GitHub returns PRs in the issues endpoint — filter them out
        Ok(issues
            .into_iter()
            .filter(|i| i.pull_request.is_none())
            .map(github_issue_to_vcs)
            .collect())
    }

    async fn get_issue(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
    ) -> AppResult<VcsIssue> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues/{issue_number}");
        let issue: GitHubIssue = self.get_json(url).await?;
        Ok(github_issue_to_vcs(issue))
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
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues");
        let mut payload = serde_json::json!({
            "title": title,
            "labels": labels,
            "assignees": assignees,
        });
        if let Some(b) = body {
            payload["body"] = serde_json::Value::String(b.to_string());
        }
        let issue: GitHubIssue = self.post_json(url, &payload).await?;
        Ok(github_issue_to_vcs(issue))
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
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues/{issue_number}");
        let mut payload = serde_json::json!({});
        if let Some(t) = title {
            payload["title"] = serde_json::Value::String(t.to_string());
        }
        if let Some(b) = body {
            payload["body"] = serde_json::Value::String(b.to_string());
        }
        if let Some(s) = state {
            payload["state"] = serde_json::Value::String(s.to_string());
        }
        if let Some(l) = labels {
            payload["labels"] = serde_json::json!(l);
        }
        if let Some(a) = assignees {
            payload["assignees"] = serde_json::json!(a);
        }
        let issue: GitHubIssue = self.patch_json(url, &payload).await?;
        Ok(github_issue_to_vcs(issue))
    }

    async fn close_issue(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
        reason: Option<&str>,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues/{issue_number}");
        let mut payload = serde_json::json!({ "state": "closed" });
        if let Some(r) = reason {
            payload["state_reason"] = serde_json::Value::String(r.to_string());
        }
        let _: GitHubIssue = self.patch_json(url, &payload).await?;
        Ok(())
    }

    async fn delete_issue(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
    ) -> AppResult<()> {
        // Fetch the node_id via REST API (required for GraphQL deleteIssue mutation)
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues/{issue_number}");
        let issue: serde_json::Value = self.get_json(url).await?;
        let node_id = issue["node_id"]
            .as_str()
            .ok_or_else(|| AppError::Provider("Issue node_id not found".to_string()))?
            .to_string();

        #[derive(Deserialize)]
        struct DeleteIssueData {
            #[serde(rename = "deleteIssue")]
            delete_issue: serde_json::Value,
        }

        let _: DeleteIssueData = self
            .graphql(
                "mutation DeleteIssue($id: ID!) { deleteIssue(input: { issueId: $id }) { clientMutationId } }",
                serde_json::json!({ "id": node_id }),
            )
            .await?;

        Ok(())
    }

    async fn list_branches(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<VcsBranch>> {
        let repo_url = format!("{GITHUB_API}/repos/{owner}/{repository}");
        let repo_info: serde_json::Value = self.get_json(repo_url).await?;
        let default_branch = repo_info["default_branch"].as_str().unwrap_or("").to_string();

        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/branches");
        let branches: Vec<GitHubBranch> = self.fetch_paginated(url).await?;

        Ok(branches
            .into_iter()
            .map(|b| VcsBranch {
                is_default: b.name == default_branch,
                is_protected: b.protected,
                sha: b.commit.sha,
                name: b.name,
            })
            .collect())
    }

    async fn create_branch(
        &self,
        owner: &str,
        repository: &str,
        branch_name: &str,
        sha: &str,
    ) -> AppResult<VcsBranch> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/git/refs");
        let payload = serde_json::json!({
            "ref": format!("refs/heads/{branch_name}"),
            "sha": sha,
        });
        let result: GitHubRef = self.post_json(url, &payload).await?;
        Ok(VcsBranch {
            name: result.r#ref.trim_start_matches("refs/heads/").to_string(),
            sha: result.object.sha,
            is_default: false,
            is_protected: false,
        })
    }

    async fn delete_branch(
        &self,
        owner: &str,
        repository: &str,
        branch_name: &str,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/git/refs/heads/{branch_name}");
        let response = self
            .client
            .delete(&url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!(
                "GitHub API error: {status} {body}"
            )));
        }

        Ok(())
    }
}
