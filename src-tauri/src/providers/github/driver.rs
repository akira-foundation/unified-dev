use async_trait::async_trait;
use serde::de::DeserializeOwned;
use serde::Deserialize;

use crate::core::provider::traits::{ProviderDriverFactory, VcsProvider};
use crate::core::provider::types::{
    ProviderAuth, ProviderKind, ProviderOrg, ProviderOrgKind, ProviderRepo, PullRequestState, VcsPullRequest,
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
                body: pr.body,
                author: pr.user.map(|u| u.login),
                labels: pr.labels.unwrap_or_default().into_iter().map(|l| l.name).collect(),
                reviewers: pr.requested_reviewers.unwrap_or_default().into_iter().map(|u| u.login).collect(),
            })
            .collect())
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
