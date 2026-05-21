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
    pub(super) async fn list_issues_impl(
        &self,
        owner: &str,
        repository: &str,
        state: Option<&str>,
    ) -> AppResult<Vec<VcsIssue>> {
        #[derive(Deserialize)]
        struct Data {
            repository: Option<RepoData>,
        }
        #[derive(Deserialize)]
        struct RepoData {
            issues: IssueConnection,
        }
        #[derive(Deserialize)]
        struct IssueConnection {
            nodes: Vec<IssueNode>,
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
        struct IssueNode {
            number: u64,
            title: String,
            body: Option<String>,
            state: String,
            #[serde(rename = "stateReason")]
            state_reason: Option<String>,
            url: String,
            #[serde(rename = "createdAt")]
            created_at: String,
            #[serde(rename = "updatedAt")]
            updated_at: String,
            author: Option<Actor>,
            labels: LabelConnection,
            assignees: AssigneeConnection,
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
            color: String,
        }
        #[derive(Deserialize)]
        struct AssigneeConnection {
            nodes: Vec<Actor>,
        }

        let states_gql = match state.unwrap_or("open") {
            "closed" => "[CLOSED]",
            "all" => "[OPEN, CLOSED]",
            _ => "[OPEN]",
        };

        let query = format!(r#"
            query($owner: String!, $repo: String!, $after: String) {{
                repository(owner: $owner, name: $repo) {{
                    issues(first: 100, after: $after, states: {states_gql}, orderBy: {{field: UPDATED_AT, direction: DESC}}) {{
                        nodes {{
                            number title body state stateReason url createdAt updatedAt
                            author {{ login }}
                            labels(first: 20) {{ nodes {{ name color }} }}
                            assignees(first: 10) {{ nodes {{ login }} }}
                        }}
                        pageInfo {{ hasNextPage endCursor }}
                    }}
                }}
            }}
        "#);

        let owner_s = owner.to_string();
        let repo_s = repository.to_string();

        let issues = self.graphql_paginated::<VcsIssue, _, Data>(
            &query,
            serde_json::json!({ "owner": owner_s, "repo": repo_s }),
            |data| {
                let conn = match data.repository {
                    Some(r) => r.issues,
                    None => return (vec![], false, None),
                };
                let items = conn.nodes.into_iter().map(|i| {
                    let label_colors = i.labels.nodes.iter().map(|l| l.color.clone()).collect();
                    let labels = i.labels.nodes.into_iter().map(|l| l.name).collect();
                    VcsIssue {
                        external_id: i.number.to_string(),
                        number: i.number,
                        title: i.title,
                        body: i.body,
                        status: i.state.to_lowercase(),
                        state_reason: i.state_reason,
                        labels,
                        label_colors,
                        assignees: i.assignees.nodes.into_iter().map(|a| a.login).collect(),
                        author: i.author.map(|a| a.login),
                        url: i.url,
                        created_at: i.created_at,
                        updated_at: i.updated_at,
                    }
                }).collect();
                (items, conn.page_info.has_next_page, conn.page_info.end_cursor)
            },
        ).await?;

        Ok(issues)
    }

    pub(super) async fn create_issue_impl(
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

    pub(super) async fn update_issue_impl(
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
        if let Some(t) = title { payload["title"] = serde_json::Value::String(t.to_string()); }
        if let Some(b) = body { payload["body"] = serde_json::Value::String(b.to_string()); }
        if let Some(s) = state { payload["state"] = serde_json::Value::String(s.to_string()); }
        if let Some(l) = labels { payload["labels"] = serde_json::json!(l); }
        if let Some(a) = assignees { payload["assignees"] = serde_json::json!(a); }
        let issue: GitHubIssue = self.patch_json(url, &payload).await?;
        Ok(github_issue_to_vcs(issue))
    }

    pub(super) async fn close_issue_impl(
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

    pub(super) async fn delete_issue_impl(
        &self,
        owner: &str,
        repository: &str,
        issue_number: u64,
    ) -> AppResult<()> {
        #[derive(Deserialize)]
        struct Data {
            repository: Option<RepoData>,
        }
        #[derive(Deserialize)]
        struct RepoData {
            issue: Option<IssueData>,
        }
        #[derive(Deserialize)]
        struct IssueData {
            id: String,
        }

        let node_query = r#"
            query($owner: String!, $repo: String!, $number: Int!) {
                repository(owner: $owner, name: $repo) {
                    issue(number: $number) { id }
                }
            }
        "#;

        let data: Data = self.graphql(node_query, serde_json::json!({
            "owner": owner,
            "repo": repository,
            "number": issue_number as i64,
        })).await?;

        let node_id = data.repository
            .and_then(|r| r.issue)
            .map(|i| i.id)
            .ok_or_else(|| AppError::Provider("Issue node_id not found".to_string()))?;

        #[derive(Deserialize)]
        struct DeleteData {
            #[serde(rename = "deleteIssue")]
            _delete_issue: serde_json::Value,
        }

        let _: DeleteData = self.graphql(
            "mutation DeleteIssue($id: ID!) { deleteIssue(input: { issueId: $id }) { clientMutationId } }",
            serde_json::json!({ "id": node_id }),
        ).await?;

        Ok(())
    }
}
