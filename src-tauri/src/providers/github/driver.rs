use async_trait::async_trait;
use serde::de::DeserializeOwned;
use serde::Deserialize;

use crate::core::provider::traits::VcsProvider;
use crate::core::provider::types::{ProviderId, PullRequestState, VcsPullRequest, VcsRepository};
use crate::error::{AppError, AppResult};

const GITHUB_API: &str = "https://api.github.com";

pub struct GitHubDriver {
    client: reqwest::Client,
}

impl GitHubDriver {
    pub fn new() -> AppResult<Self> {
        let client = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?;

        Ok(Self { client })
    }

    async fn get_json<T: DeserializeOwned>(&self, url: String, token: &str) -> AppResult<T> {
        let response = self
            .client
            .get(url)
            .bearer_auth(token)
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

    async fn fetch_paginated<T: DeserializeOwned>(
        &self,
        mut url: String,
        token: &str,
    ) -> AppResult<Vec<T>> {
        let mut page = 1;
        let mut results = Vec::new();

        loop {
            let separator = if url.contains('?') { '&' } else { '?' };
            let paged_url = format!("{url}{separator}per_page=100&page={page}");
            let chunk: Vec<T> = self.get_json(paged_url, token).await?;
            if chunk.is_empty() {
                break;
            }
            results.extend(chunk);
            page += 1;
        }

        Ok(results)
    }
}

#[async_trait]
impl VcsProvider for GitHubDriver {
    fn id(&self) -> ProviderId {
        ProviderId::GitHub
    }

    fn name(&self) -> &str {
        "GitHub"
    }

    async fn list_repositories(&self, organization: &str, token: &str) -> AppResult<Vec<VcsRepository>> {
        let url = format!("{GITHUB_API}/orgs/{organization}/repos?type=all");
        let repositories: Vec<GitHubRepo> = self.fetch_paginated(url, token).await?;

        Ok(repositories
            .into_iter()
            .map(|repo| VcsRepository {
                id: repo.id.to_string(),
                owner: repo.owner.login,
                name: repo.name,
                full_name: repo.full_name,
                default_branch: repo.default_branch,
                is_private: repo.private,
            })
            .collect())
    }

    async fn list_pull_requests(
        &self,
        owner: &str,
        repository: &str,
        token: &str,
    ) -> AppResult<Vec<VcsPullRequest>> {
        let url = format!(
            "{GITHUB_API}/repos/{owner}/{repository}/pulls?state=all"
        );
        let pulls: Vec<GitHubPullRequest> = self.fetch_paginated(url, token).await?;

        Ok(pulls
            .into_iter()
            .map(|pr| VcsPullRequest {
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
                updated_at: pr.updated_at,
                is_draft: pr.draft.unwrap_or(false),
                merged_at: pr.merged_at,
            })
            .collect())
    }
}

#[derive(Debug, Deserialize)]
struct GitHubRepoOwner {
    login: String,
}

#[derive(Debug, Deserialize)]
struct GitHubRepo {
    id: u64,
    name: String,
    full_name: String,
    owner: GitHubRepoOwner,
    default_branch: String,
    private: bool,
}

#[derive(Debug, Deserialize)]
struct GitHubPullReference {
    #[serde(rename = "ref")]
    reference: String,
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
}
