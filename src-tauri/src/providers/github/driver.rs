use async_trait::async_trait;
use serde::de::DeserializeOwned;
use serde::Deserialize;

use crate::core::provider::traits::{VcsProvider, VcsProviderFactory};
use crate::core::provider::types::{ProviderAuth, ProviderId, ProviderRepo, PullRequestState, VcsPullRequest};
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

    async fn fetch_paginated<T: DeserializeOwned>(
        &self,
        mut url: String,
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

impl VcsProviderFactory for GitHubFactory {
    fn id(&self) -> ProviderId {
        ProviderId::GitHub
    }

    fn name(&self) -> &str {
        "GitHub"
    }

    fn create(&self, auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        let token = auth_token(&auth)?.to_string();
        Ok(std::sync::Arc::new(GitHubDriver::new(token)?))
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

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
        let url = format!("{GITHUB_API}/user/repos?type=all");
        let repositories: Vec<GitHubRepo> = self.fetch_paginated(url).await?;

        Ok(repositories
            .into_iter()
            .map(|repo| ProviderRepo {
                id: repo.id.to_string(),
                owner: repo.owner.login,
                name: repo.name,
                visibility: if repo.private { "private".to_string() } else { "public".to_string() },
                is_private: repo.private,
            })
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

fn auth_token(auth: &ProviderAuth) -> AppResult<&str> {
    match auth {
        ProviderAuth::Pat { token } => Ok(token.as_str()),
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
