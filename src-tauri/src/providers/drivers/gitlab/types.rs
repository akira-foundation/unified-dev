use serde::Deserialize;

use crate::providers::dto::{ProviderRepo, VcsPullRequest};
use crate::providers::enums::PullRequestState;

pub fn urlencoded(s: &str) -> String {
    s.replace('/', "%2F")
}

pub fn project_to_provider(project: GitLabProject) -> ProviderRepo {
    let is_private = project.visibility == "private";
    let owner = project
        .namespace
        .as_ref()
        .map(|ns| ns.path.clone())
        .unwrap_or_default();

    ProviderRepo {
        id: project.id.to_string(),
        owner,
        name: project.path,
        visibility: project.visibility,
        is_private,
        default_branch: project.default_branch.unwrap_or_else(|| "main".to_string()),
    }
}

pub fn mr_to_pull_request(mr: GitLabMergeRequest) -> VcsPullRequest {
    VcsPullRequest {
        id: mr.id.to_string(),
        number: mr.iid,
        title: mr.title,
        state: match mr.state.as_str() {
            "opened" => PullRequestState::Open,
            _ => PullRequestState::Closed,
        },
        url: mr.web_url,
        head: mr.source_branch,
        base: mr.target_branch,
        head_sha: "".to_string(),
        updated_at: mr.updated_at,
        is_draft: mr.draft.unwrap_or(false),
        merged_at: mr.merged_at,
        body: mr.description,
        author: mr.author.map(|u| u.username),
        labels: mr.labels.unwrap_or_default(),
        reviewers: mr
            .reviewers
            .unwrap_or_default()
            .into_iter()
            .map(|u| u.username)
            .collect(),
        ci_status: None,
    }
}

#[derive(Debug, Deserialize)]
pub struct GitLabUser {
    pub id: u64,
    pub username: String,
}

#[derive(Debug, Deserialize)]
pub struct GitLabGroup {
    pub id: u64,
    pub path: String,
}

#[derive(Debug, Deserialize)]
pub struct GitLabNamespace {
    pub path: String,
}

#[derive(Debug, Deserialize)]
pub struct GitLabProject {
    pub id: u64,
    pub path: String,
    pub visibility: String,
    pub default_branch: Option<String>,
    pub namespace: Option<GitLabNamespace>,
}

#[derive(Debug, Deserialize)]
pub struct GitLabMergeRequestUser {
    pub username: String,
}

#[derive(Debug, Deserialize)]
pub struct GitLabMergeRequest {
    pub id: u64,
    pub iid: u64,
    pub title: String,
    pub state: String,
    pub web_url: String,
    pub source_branch: String,
    pub target_branch: String,
    pub updated_at: String,
    pub draft: Option<bool>,
    pub merged_at: Option<String>,
    pub description: Option<String>,
    pub author: Option<GitLabMergeRequestUser>,
    pub labels: Option<Vec<String>>,
    pub reviewers: Option<Vec<GitLabMergeRequestUser>>,
}
