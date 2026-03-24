use async_trait::async_trait;
use futures_util::future::join_all;
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::core::provider::traits::{ProviderDriverFactory, VcsProvider};
use crate::core::provider::types::{
    ProviderAuth, ProviderKind, ProviderOrg, ProviderOrgKind, ProviderRepo, PrMergeStrategy,
    PrReviewEvent, PullRequestState, VcsCiCheck, VcsCiCheckStep, VcsPrComment, VcsPrFile, VcsPullRequest,
};
use crate::error::{AppError, AppResult};

const GITHUB_API: &str = "https://api.github.com";

pub struct GitHubDriver {
    client: reqwest::Client,
    token: String,
}

impl GitHubDriver {
    pub fn new(token: String) -> AppResult<Self> {
        let client = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?;

        Ok(Self { client, token })
    }

    async fn get_json<T: DeserializeOwned>(&self, url: String) -> AppResult<T> {
        let response = self
            .client
            .get(url)
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

        Ok(response.json::<T>().await?)
    }

    async fn get_text(&self, url: String) -> AppResult<String> {
        let response = self
            .client
            .get(url)
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

        Ok(response.text().await?)
    }

    async fn get_redirect_url(&self, url: String) -> AppResult<String> {
        // Build a client that does NOT follow redirects so we can get the Location header.
        let no_redirect = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .redirect(reqwest::redirect::Policy::none())
            .build()?;

        let response = no_redirect
            .get(&url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .send()
            .await?;

        let status = response.status();
        if status.is_redirection() {
            let location = response
                .headers()
                .get("location")
                .and_then(|v| v.to_str().ok())
                .ok_or_else(|| AppError::Provider("Missing Location header in redirect".to_string()))?
                .to_string();
            return Ok(location);
        }

        // Not a redirect — treat the body as the content URL (or error)
        if !status.is_success() {
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("GitHub API error: {status} {body}")));
        }

        // Already text — return the body as-is (unexpected but handle gracefully)
        Ok(response.text().await?)
    }

    async fn post_json<B: Serialize + Send + Sync, T: DeserializeOwned>(
        &self,
        url: String,
        payload: &B,
    ) -> AppResult<T> {
        let response = self
            .client
            .post(url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .json(payload)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!(
                "GitHub API error: {status} {body}"
            )));
        }

        Ok(response.json::<T>().await?)
    }

    async fn put_json<B: Serialize + Send + Sync>(
        &self,
        url: String,
        payload: &B,
    ) -> AppResult<()> {
        let response = self
            .client
            .put(url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .json(payload)
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

    async fn fetch_paginated<T: DeserializeOwned>(
        &self,
        url: String,
    ) -> AppResult<Vec<T>> {
        let mut page = 1;
        let mut results = Vec::new();

        loop {
            let separator = if url.contains('?') { '&' } else { '?' };
            let paged_url = format!("{url}{separator}per_page=100&page={page}");
            let chunk: Vec<T> = self.get_json(paged_url).await?;
            if chunk.is_empty() {
                break;
            }
            results.extend(chunk);
            page += 1;
        }

        Ok(results)
    }
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
        let repositories: Vec<GitHubRepo> = self.fetch_paginated(url).await?;

        Ok(repositories
            .into_iter()
            .map(repo_to_provider)
            .collect())
    }

    async fn list_organization_repositories(&self, organization: &str) -> AppResult<Vec<ProviderRepo>> {
        let url = format!("{GITHUB_API}/orgs/{organization}/repos?type=all");
        let repositories: Vec<GitHubRepo> = self.fetch_paginated(url).await?;

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
}

fn repo_to_provider(repo: GitHubRepo) -> ProviderRepo {
    ProviderRepo {
        id: repo.id.to_string(),
        owner: repo.owner.login,
        name: repo.name,
        visibility: if repo.private { "private".to_string() } else { "public".to_string() },
        is_private: repo.private,
        default_branch: repo.default_branch,
    }
}

#[derive(Debug, Deserialize)]
struct GitHubRepoOwner {
    login: String,
}

#[derive(Debug, Deserialize)]
struct GitHubUser {
    id: u64,
    login: String,
}

#[derive(Debug, Deserialize)]
struct GitHubOrg {
    id: u64,
    login: String,
}

#[derive(Debug, Deserialize)]
struct GitHubRepo {
    id: u64,
    name: String,
    #[allow(dead_code)]
    full_name: String,
    owner: GitHubRepoOwner,
    default_branch: String,
    private: bool,
}

#[derive(Debug, Deserialize)]
struct GitHubPullReference {
    #[serde(rename = "ref")]
    reference: String,
    sha: String,
}

#[derive(Debug, Deserialize)]
struct GitHubPullUser {
    login: String,
}

#[derive(Debug, Deserialize)]
struct GitHubPullLabel {
    name: String,
}

#[derive(Debug, Deserialize)]
struct GitHubPullRequest {
    id: u64,
    number: u64,
    title: String,
    state: String,
    html_url: String,
    updated_at: String,
    merged_at: Option<String>,
    draft: Option<bool>,
    head: GitHubPullReference,
    base: GitHubPullReference,
    body: Option<String>,
    user: Option<GitHubPullUser>,
    labels: Option<Vec<GitHubPullLabel>>,
    requested_reviewers: Option<Vec<GitHubPullUser>>,
}

#[derive(Debug, Deserialize)]
struct GitHubCheckRunsResponse {
    total_count: u64,
    check_runs: Vec<GitHubCheckRun>,
}

#[derive(Debug, Deserialize)]
struct GitHubCheckRun {
    id: u64,
    name: String,
    status: String,
    conclusion: Option<String>,
    started_at: Option<String>,
    completed_at: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GitHubJobResponse {
    steps: Option<Vec<GitHubJobStep>>,
}

#[derive(Debug, Deserialize)]
struct GitHubJobStep {
    number: u64,
    name: String,
    status: String,
    conclusion: Option<String>,
    started_at: Option<String>,
    completed_at: Option<String>,
}

#[derive(Debug, Deserialize)]
struct GitHubCommentUser {
    login: String,
}

#[derive(Debug, Deserialize)]
struct GitHubIssueComment {
    id: u64,
    user: Option<GitHubCommentUser>,
    body: Option<String>,
    created_at: String,
}

#[derive(Debug, Deserialize)]
struct GitHubPrFile {
    filename: String,
    status: String,
    additions: u64,
    deletions: u64,
    patch: Option<String>,
}
