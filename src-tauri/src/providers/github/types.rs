use serde::Deserialize;

use crate::providers::shared::types::{ProviderRepo, VcsIssue};

pub fn repo_to_provider(repo: GitHubRepo) -> ProviderRepo {
    ProviderRepo {
        id: repo.id.to_string(),
        owner: repo.owner.login,
        name: repo.name,
        visibility: if repo.private {
            "private".to_string()
        } else {
            "public".to_string()
        },
        is_private: repo.private,
        default_branch: repo.default_branch,
    }
}

pub fn github_issue_to_vcs(issue: GitHubIssue) -> VcsIssue {
    let labels_vec = issue.labels.unwrap_or_default();
    let label_colors: Vec<String> = labels_vec
        .iter()
        .map(|l| l.color.clone().unwrap_or_default())
        .collect();
    let labels: Vec<String> = labels_vec.into_iter().map(|l| l.name).collect();

    VcsIssue {
        external_id: issue.number.to_string(),
        number: issue.number,
        title: issue.title,
        body: issue.body,
        status: issue.state,
        state_reason: issue.state_reason,
        labels,
        label_colors,
        assignees: issue
            .assignees
            .unwrap_or_default()
            .into_iter()
            .map(|u| u.login)
            .collect(),
        author: issue.user.map(|u| u.login),
        url: issue.html_url,
        created_at: issue.created_at,
        updated_at: issue.updated_at,
    }
}

#[derive(Debug, Deserialize)]
pub struct GitHubRepoOwner {
    pub login: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubUser {
    pub id: u64,
    pub login: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubOrg {
    pub id: u64,
    pub login: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubRepo {
    pub id: u64,
    pub name: String,
    #[allow(dead_code)]
    pub full_name: String,
    pub owner: GitHubRepoOwner,
    pub default_branch: String,
    pub private: bool,
}

#[derive(Debug, Deserialize)]
pub struct GitHubPullReference {
    #[serde(rename = "ref")]
    pub reference: String,
    pub sha: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubPullUser {
    pub login: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubPullLabel {
    pub name: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubPullRequest {
    pub id: u64,
    pub number: u64,
    pub title: String,
    pub state: String,
    pub html_url: String,
    pub updated_at: String,
    pub merged_at: Option<String>,
    pub draft: Option<bool>,
    pub head: GitHubPullReference,
    pub base: GitHubPullReference,
    pub body: Option<String>,
    pub user: Option<GitHubPullUser>,
    pub labels: Option<Vec<GitHubPullLabel>>,
    pub requested_reviewers: Option<Vec<GitHubPullUser>>,
}

#[derive(Debug, Deserialize)]
pub struct GitHubCheckRunsResponse {
    pub total_count: u64,
    pub check_runs: Vec<GitHubCheckRun>,
}

#[derive(Debug, Deserialize)]
pub struct GitHubCheckRun {
    pub id: u64,
    pub name: String,
    pub status: String,
    pub conclusion: Option<String>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct GitHubJobResponse {
    pub steps: Option<Vec<GitHubJobStep>>,
}

#[derive(Debug, Deserialize)]
pub struct GitHubJobStep {
    pub number: u64,
    pub name: String,
    pub status: String,
    pub conclusion: Option<String>,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct GitHubCommentUser {
    pub login: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubIssueComment {
    pub id: u64,
    pub user: Option<GitHubCommentUser>,
    pub body: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubPrFile {
    pub filename: String,
    pub status: String,
    pub additions: u64,
    pub deletions: u64,
    pub patch: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct GitHubIssueUser {
    pub login: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubIssueLabel {
    pub name: String,
    pub color: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct GitHubIssue {
    pub number: u64,
    pub title: String,
    pub body: Option<String>,
    pub state: String,
    pub state_reason: Option<String>,
    pub html_url: String,
    pub user: Option<GitHubIssueUser>,
    pub labels: Option<Vec<GitHubIssueLabel>>,
    pub assignees: Option<Vec<GitHubIssueUser>>,
    pub created_at: String,
    pub updated_at: String,
    // Present when the issue is actually a PR
    pub pull_request: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
pub struct GitHubBranchCommit {
    pub sha: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubBranch {
    pub name: String,
    pub commit: GitHubBranchCommit,
    pub protected: bool,
}

#[derive(Debug, Deserialize)]
pub struct GitHubRefObject {
    pub sha: String,
}

#[derive(Debug, Deserialize)]
pub struct GitHubRef {
    pub r#ref: String,
    pub object: GitHubRefObject,
}
