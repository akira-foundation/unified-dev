use async_trait::async_trait;
use serde::de::DeserializeOwned;
use serde::Deserialize;

use crate::core::provider::traits::{ProviderDriverFactory, VcsProvider};
use crate::core::provider::types::{
    ProviderAuth, ProviderKind, ProviderOrg, ProviderOrgKind, ProviderRepo, PullRequestState, VcsPullRequest,
};
use crate::error::{AppError, AppResult};

const BITBUCKET_API: &str = "https://api.bitbucket.org/2.0";

pub struct BitbucketDriver {
    client: reqwest::Client,
    username: String,
    password: String,
}

impl BitbucketDriver {
    pub fn new(username: String, password: String) -> AppResult<Self> {
        let client = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?;

        Ok(Self { client, username, password })
    }

    async fn get_json<T: DeserializeOwned>(&self, url: &str) -> AppResult<T> {
        let response = self
            .client
            .get(url)
            .basic_auth(&self.username, Some(&self.password))
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("Bitbucket API error: {status} {body}")));
        }

        Ok(response.json::<T>().await?)
    }

    async fn fetch_paginated<T: DeserializeOwned>(&self, base_url: &str) -> AppResult<Vec<T>> {
        let mut results = Vec::new();
        let separator = if base_url.contains('?') { '&' } else { '?' };
        let first_url = format!("{base_url}{separator}pagelen=100");
        let mut next_url: Option<String> = Some(first_url);

        while let Some(url) = next_url {
            let page: BitbucketPage<T> = self.get_json(&url).await?;
            results.extend(page.values);
            next_url = page.next;
        }

        Ok(results)
    }
}

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
}

fn repo_to_provider(repo: BitbucketRepo) -> ProviderRepo {
    let owner = repo
        .workspace
        .as_ref()
        .map(|ws| ws.slug.clone())
        .unwrap_or_default();
    let is_private = repo.is_private.unwrap_or(false);
    let default_branch = repo
        .mainbranch
        .as_ref()
        .map(|b| b.name.clone())
        .unwrap_or_else(|| "main".to_string());

    ProviderRepo {
        id: repo.uuid.unwrap_or_else(|| repo.slug.clone()),
        owner,
        name: repo.slug,
        visibility: if is_private { "private".to_string() } else { "public".to_string() },
        is_private,
        default_branch,
    }
}

fn pr_to_pull_request(pr: BitbucketPullRequest) -> VcsPullRequest {
    VcsPullRequest {
        id: pr.id.to_string(),
        number: pr.id,
        title: pr.title,
        state: match pr.state.as_str() {
            "OPEN" => PullRequestState::Open,
            _ => PullRequestState::Closed,
        },
        url: pr.links.and_then(|l| l.html).map(|h| h.href).unwrap_or_default(),
        head: pr.source.branch.name,
        base: pr.destination.branch.name,
        updated_at: pr.updated_on,
        is_draft: false,
        merged_at: None,
    }
}

#[derive(Debug, Deserialize)]
struct BitbucketPage<T> {
    values: Vec<T>,
    next: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BitbucketUser {
    account_id: String,
    username: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BitbucketWorkspace {
    slug: String,
    uuid: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BitbucketMainBranch {
    name: String,
}

#[derive(Debug, Deserialize)]
struct BitbucketRepoWorkspace {
    slug: String,
}

#[derive(Debug, Deserialize)]
struct BitbucketRepo {
    slug: String,
    uuid: Option<String>,
    is_private: Option<bool>,
    workspace: Option<BitbucketRepoWorkspace>,
    mainbranch: Option<BitbucketMainBranch>,
}

#[derive(Debug, Deserialize)]
struct BitbucketPrBranch {
    name: String,
}

#[derive(Debug, Deserialize)]
struct BitbucketPrEndpoint {
    branch: BitbucketPrBranch,
}

#[derive(Debug, Deserialize)]
struct BitbucketLinkHref {
    href: String,
}

#[derive(Debug, Deserialize)]
struct BitbucketPrLinks {
    html: Option<BitbucketLinkHref>,
}

#[derive(Debug, Deserialize)]
struct BitbucketPullRequest {
    id: u64,
    title: String,
    state: String,
    source: BitbucketPrEndpoint,
    destination: BitbucketPrEndpoint,
    updated_on: String,
    links: Option<BitbucketPrLinks>,
}
