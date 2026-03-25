use serde::Deserialize;

use crate::providers::shared::types::{ProviderRepo, PullRequestState, VcsPullRequest};

pub fn repo_to_provider(repo: BitbucketRepo) -> ProviderRepo {
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
        visibility: if is_private {
            "private".to_string()
        } else {
            "public".to_string()
        },
        is_private,
        default_branch,
    }
}

pub fn pr_to_pull_request(pr: BitbucketPullRequest) -> VcsPullRequest {
    VcsPullRequest {
        id: pr.id.to_string(),
        number: pr.id,
        title: pr.title,
        state: match pr.state.as_str() {
            "OPEN" => PullRequestState::Open,
            _ => PullRequestState::Closed,
        },
        url: pr
            .links
            .and_then(|l| l.html)
            .map(|h| h.href)
            .unwrap_or_default(),
        head: pr.source.branch.name,
        base: pr.destination.branch.name,
        head_sha: "".to_string(),
        updated_at: pr.updated_on,
        is_draft: false,
        merged_at: None,
        body: pr.description,
        author: pr.author.map(|a| a.display_name),
        labels: vec![],
        reviewers: pr
            .reviewers
            .unwrap_or_default()
            .into_iter()
            .map(|r| r.display_name)
            .collect(),
        ci_status: None,
    }
}

#[derive(Debug, Deserialize)]
pub struct BitbucketUser {
    pub account_id: String,
    pub username: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketWorkspace {
    pub slug: String,
    pub uuid: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketMainBranch {
    pub name: String,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketRepoWorkspace {
    pub slug: String,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketRepo {
    pub slug: String,
    pub uuid: Option<String>,
    pub is_private: Option<bool>,
    pub workspace: Option<BitbucketRepoWorkspace>,
    pub mainbranch: Option<BitbucketMainBranch>,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketPrBranch {
    pub name: String,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketPrEndpoint {
    pub branch: BitbucketPrBranch,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketLinkHref {
    pub href: String,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketPrLinks {
    pub html: Option<BitbucketLinkHref>,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketPrAuthor {
    pub display_name: String,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketPrReviewer {
    pub display_name: String,
}

#[derive(Debug, Deserialize)]
pub struct BitbucketPullRequest {
    pub id: u64,
    pub title: String,
    pub state: String,
    pub source: BitbucketPrEndpoint,
    pub destination: BitbucketPrEndpoint,
    pub updated_on: String,
    pub links: Option<BitbucketPrLinks>,
    pub description: Option<String>,
    pub author: Option<BitbucketPrAuthor>,
    pub reviewers: Option<Vec<BitbucketPrReviewer>>,
}
