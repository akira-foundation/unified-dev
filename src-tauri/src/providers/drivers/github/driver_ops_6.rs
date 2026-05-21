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
    pub(super) async fn list_branches_impl(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<VcsBranch>> {
        #[derive(Deserialize)]
        struct Data {
            repository: Option<RepoData>,
        }
        #[derive(Deserialize)]
        struct RepoData {
            #[serde(rename = "defaultBranchRef")]
            default_branch_ref: Option<DefaultRef>,
            refs: RefConnection,
        }
        #[derive(Deserialize)]
        struct DefaultRef {
            name: String,
        }
        #[derive(Deserialize)]
        struct RefConnection {
            nodes: Vec<RefNode>,
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
        struct RefNode {
            name: String,
            #[serde(rename = "branchProtectionRule")]
            branch_protection_rule: Option<serde_json::Value>,
            target: Option<RefTarget>,
        }
        #[derive(Deserialize)]
        struct RefTarget {
            oid: String,
        }

        let query = r#"
            query($owner: String!, $repo: String!, $after: String) {
                repository(owner: $owner, name: $repo) {
                    defaultBranchRef { name }
                    refs(refPrefix: "refs/heads/", first: 100, after: $after) {
                        nodes {
                            name
                            branchProtectionRule { id }
                            target { oid }
                        }
                        pageInfo { hasNextPage endCursor }
                    }
                }
            }
        "#;

        let owner_s = owner.to_string();
        let repo_s = repository.to_string();

        #[derive(Clone)]
        struct DefaultBranchHolder(std::sync::Arc<std::sync::Mutex<Option<String>>>);

        let default_holder = DefaultBranchHolder(std::sync::Arc::new(std::sync::Mutex::new(None)));
        let default_holder_clone = default_holder.clone();

        let branches = self.graphql_paginated::<VcsBranch, _, Data>(
            query,
            serde_json::json!({ "owner": owner_s, "repo": repo_s }),
            move |data| {
                let repo = match data.repository {
                    Some(r) => r,
                    None => return (vec![], false, None),
                };

                if let Ok(mut lock) = default_holder_clone.0.lock() {
                    if lock.is_none() {
                        *lock = repo.default_branch_ref.map(|d| d.name);
                    }
                }

                let default_name = default_holder_clone.0.lock().ok()
                    .and_then(|l| l.clone())
                    .unwrap_or_default();

                let items = repo.refs.nodes.into_iter().map(|r| VcsBranch {
                    is_default: r.name == default_name,
                    is_protected: r.branch_protection_rule.is_some(),
                    sha: r.target.map(|t| t.oid).unwrap_or_default(),
                    name: r.name,
                }).collect();

                (items, repo.refs.page_info.has_next_page, repo.refs.page_info.end_cursor)
            },
        ).await?;

        Ok(branches)
    }

    pub(super) async fn create_branch_impl(
        &self,
        owner: &str,
        repository: &str,
        branch_name: &str,
        sha: &str,
    ) -> AppResult<VcsBranch> {
        use super::types::GitHubRef;
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/git/refs");
        let payload = serde_json::json!({
            "ref": format!("refs/heads/{branch_name}"),
            "sha": sha,
        });
        let result: GitHubRef = self.post_json(url, &payload).await?;
        Ok(VcsBranch {
            name: result.r#ref.trim_start_matches("refs/heads/").to_string(),
            sha: result.object.sha,
            is_default: false,
            is_protected: false,
        })
    }

    pub(super) async fn delete_branch_impl(
        &self,
        owner: &str,
        repository: &str,
        branch_name: &str,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/git/refs/heads/{branch_name}");
        let response = self
            .client
            .delete(&url)
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

        Ok(())
    }
}
