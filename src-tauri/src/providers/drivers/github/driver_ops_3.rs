#![allow(unused_imports)]
use serde::Deserialize;

use crate::providers::dto::{CreatedRepo, ProviderOrg, ProviderRepo, VcsBranch, VcsCiCheck, VcsCiCheckStep, VcsPrComment, VcsPrFile, VcsPullRequest, VcsIssue};
use crate::providers::enums::{ProviderOrgKind, PrMergeStrategy, PrReviewEvent, PullRequestState};
use crate::app::support::error::{AppError, AppResult};

use super::client::{GitHubDriver, GITHUB_API};
use super::types::{
    github_issue_to_vcs, GitHubCheckRunsResponse, GitHubIssue,
    GitHubIssueComment, GitHubJobResponse, GitHubPrFile,
};
use super::driver::list_installation_repositories;

impl GitHubDriver {
    pub(super) async fn list_pull_requests_impl(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<VcsPullRequest>> {
        #[derive(Deserialize)]
        struct Data {
            repository: Option<RepoData>,
        }
        #[derive(Deserialize)]
        struct RepoData {
            #[serde(rename = "pullRequests")]
            pull_requests: PrConnection,
        }
        #[derive(Deserialize)]
        struct PrConnection {
            nodes: Vec<PrNode>,
            #[serde(rename = "pageInfo")]
            page_info: PageInfo,
        }
        #[derive(Deserialize)]
        struct PageInfo {
            #[serde(rename = "hasNextPage")]
            has_next_page: bool,
            #[serde(rename = "endCursor")]
            end_cursor: Option<String>,
        }
        #[derive(Deserialize)]
        struct PrNode {
            number: u64,
            title: String,
            state: String,
            url: String,
            #[serde(rename = "isDraft")]
            is_draft: bool,
            #[serde(rename = "createdAt")]
            created_at: String,
            #[serde(rename = "updatedAt")]
            updated_at: String,
            #[serde(rename = "mergedAt")]
            merged_at: Option<String>,
            body: Option<String>,
            author: Option<Actor>,
            #[serde(rename = "headRefName")]
            head_ref_name: String,
            #[serde(rename = "baseRefName")]
            base_ref_name: String,
            #[serde(rename = "headRefOid")]
            head_ref_oid: String,
            labels: LabelConnection,
            #[serde(rename = "reviewRequests")]
            review_requests: ReviewRequestConnection,
            #[serde(rename = "commits")]
            commits: Option<CommitConnection>,
        }
        #[derive(Deserialize)]
        struct Actor {
            login: String,
        }
        #[derive(Deserialize)]
        struct LabelConnection {
            nodes: Vec<LabelNode>,
        }
        #[derive(Deserialize)]
        struct LabelNode {
            name: String,
        }
        #[derive(Deserialize)]
        struct ReviewRequestConnection {
            nodes: Vec<ReviewRequestNode>,
        }
        #[derive(Deserialize)]
        struct ReviewRequestNode {
            #[serde(rename = "requestedReviewer")]
            requested_reviewer: Option<RequestedReviewer>,
        }
        #[derive(Deserialize)]
        #[serde(tag = "__typename")]
        enum RequestedReviewer {
            User { login: String },
            Team { name: String },
            #[serde(other)]
            Unknown,
        }
        #[derive(Deserialize)]
        struct CommitConnection {
            nodes: Vec<Option<CommitNode>>,
        }
        #[derive(Deserialize)]
        struct CommitNode {
            commit: CommitDetail,
        }
        #[derive(Deserialize)]
        struct CommitDetail {
            #[serde(rename = "statusCheckRollup")]
            status_check_rollup: Option<StatusCheckRollup>,
        }
        #[derive(Deserialize)]
        struct StatusCheckRollup {
            state: String,
        }

        let query = r#"
            query($owner: String!, $repo: String!, $after: String) {
                repository(owner: $owner, name: $repo) {
                    pullRequests(first: 100, after: $after, states: [OPEN, CLOSED, MERGED], orderBy: {field: UPDATED_AT, direction: DESC}) {
                        nodes {
                            number title state url isDraft createdAt updatedAt mergedAt body
                            headRefName baseRefName headRefOid
                            author { login }
                            labels(first: 20) { nodes { name } }
                            reviewRequests(first: 10) {
                                nodes {
                                    requestedReviewer {
                                        __typename
                                        ... on User { login }
                                        ... on Team { name }
                                    }
                                }
                            }
                            commits(last: 1) {
                                nodes {
                                    commit {
                                        statusCheckRollup { state }
                                    }
                                }
                            }
                        }
                        pageInfo { hasNextPage endCursor }
                    }
                }
            }
        "#;

        let owner_s = owner.to_string();
        let repo_s = repository.to_string();

        let prs = self.graphql_paginated::<VcsPullRequest, _, Data>(
            query,
            serde_json::json!({ "owner": owner_s, "repo": repo_s }),
            |data| {
                let conn = match data.repository {
                    Some(r) => r.pull_requests,
                    None => return (vec![], false, None),
                };
                let items = conn.nodes.into_iter().map(|pr| {
                    let ci_status = pr.commits
                        .and_then(|c| c.nodes.into_iter().next())
                        .and_then(|c| c)
                        .and_then(|c| c.commit.status_check_rollup)
                        .map(|s| match s.state.as_str() {
                            "SUCCESS" => "success".to_string(),
                            "FAILURE" | "ERROR" => "failure".to_string(),
                            _ => "pending".to_string(),
                        });

                    let reviewers = pr.review_requests.nodes.into_iter()
                        .filter_map(|r| r.requested_reviewer)
                        .filter_map(|r| match r {
                            RequestedReviewer::User { login } => Some(login),
                            RequestedReviewer::Team { name } => Some(name),
                            RequestedReviewer::Unknown => None,
                        })
                        .collect();

                    VcsPullRequest {
                        id: pr.number.to_string(),
                        number: pr.number,
                        title: pr.title,
                        state: match pr.state.as_str() {
                            "OPEN" => PullRequestState::Open,
                            _ => PullRequestState::Closed,
                        },
                        url: pr.url,
                        head: pr.head_ref_name,
                        base: pr.base_ref_name,
                        head_sha: pr.head_ref_oid,
                        created_at: pr.created_at,
                        updated_at: pr.updated_at,
                        is_draft: pr.is_draft,
                        merged_at: pr.merged_at,
                        body: pr.body,
                        author: pr.author.map(|a| a.login),
                        labels: pr.labels.nodes.into_iter().map(|l| l.name).collect(),
                        reviewers,
                        ci_status,
                    }
                }).collect();
                (items, conn.page_info.has_next_page, conn.page_info.end_cursor)
            },
        ).await?;

        Ok(prs)
    }

    pub(super) async fn get_pull_request_comments_impl(
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

    pub(super) async fn post_pull_request_comment_impl(
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

    pub(super) async fn delete_pull_request_comment_impl(
        &self,
        owner: &str,
        repository: &str,
        comment_id: &str,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues/comments/{comment_id}");
        self.delete(url).await
    }
}
