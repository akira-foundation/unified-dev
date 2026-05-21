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
    pub(super) async fn list_organization_repositories_impl(&self, organization: &str) -> AppResult<Vec<ProviderRepo>> {
        if let Ok(repositories) = list_installation_repositories(self).await {
            let mut repos = repositories
                .into_iter()
                .filter(|repo| repo.owner.login == organization)
                .map(|repo| ProviderRepo {
                    id: repo.id.to_string(),
                    owner: repo.owner.login,
                    name: repo.name,
                    visibility: repo.visibility,
                    is_private: repo.private,
                    default_branch: repo.default_branch.unwrap_or_default(),
                    is_fork: repo.fork.unwrap_or(false),
                    fork_owner: None,
                    fork_repo: None,
                })
                .collect::<Vec<_>>();

            repos.sort_by(|a, b| a.name.cmp(&b.name));

            return Ok(repos);
        }

        #[derive(Deserialize)]
        struct Data {
            organization: Option<OrgData>,
        }
        #[derive(Deserialize)]
        struct OrgData {
            repositories: RepoConnection,
        }
        #[derive(Deserialize)]
        struct RepoConnection {
            nodes: Vec<RepoNode>,
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
        struct RepoNode {
            #[serde(rename = "databaseId")]
            database_id: u64,
            name: String,
            #[serde(rename = "nameWithOwner")]
            name_with_owner: String,
            #[serde(rename = "isPrivate")]
            is_private: bool,
            #[serde(rename = "isFork")]
            is_fork: bool,
            #[serde(rename = "defaultBranchRef")]
            default_branch_ref: Option<DefaultBranchRef>,
            parent: Option<ParentRepo>,
        }
        #[derive(Deserialize)]
        struct DefaultBranchRef {
            name: String,
        }
        #[derive(Deserialize)]
        struct ParentRepo {
            name: String,
            owner: ParentRepoOwner,
        }
        #[derive(Deserialize)]
        struct ParentRepoOwner {
            login: String,
        }

        let query = r#"
            query($login: String!, $after: String) {
                organization(login: $login) {
                    repositories(first: 100, after: $after) {
                        nodes {
                            databaseId name nameWithOwner isPrivate isFork
                            defaultBranchRef { name }
                            parent { name owner { login } }
                        }
                        pageInfo { hasNextPage endCursor }
                    }
                }
            }
        "#;

        let org_login = organization.to_string();
        let repos = self.graphql_paginated::<ProviderRepo, _, Data>(
            query,
            serde_json::json!({ "login": org_login }),
            move |data| {
                let conn = match data.organization {
                    Some(o) => o.repositories,
                    None => return (vec![], false, None),
                };
                let items = conn.nodes.into_iter().map(|r| {
                    let owner = r.name_with_owner.split('/').next().unwrap_or("").to_string();
                    let (fork_owner, fork_repo) = match &r.parent {
                        Some(p) => (Some(p.owner.login.clone()), Some(p.name.clone())),
                        None => (None, None),
                    };
                    ProviderRepo {
                        id: r.database_id.to_string(),
                        owner,
                        name: r.name,
                        visibility: if r.is_private { "private".to_string() } else { "public".to_string() },
                        is_private: r.is_private,
                        default_branch: r.default_branch_ref.map(|b| b.name).unwrap_or_default(),
                        is_fork: r.is_fork,
                        fork_owner,
                        fork_repo,
                    }
                }).collect();
                (items, conn.page_info.has_next_page, conn.page_info.end_cursor)
            },
        ).await?;

        Ok(repos)
    }

    pub(super) async fn create_repository_impl(&self, org_login: Option<&str>, name: &str, description: Option<&str>, private: bool) -> AppResult<CreatedRepo> {
        #[derive(serde::Serialize)]
        struct Payload<'a> {
            name: &'a str,
            #[serde(skip_serializing_if = "Option::is_none")]
            description: Option<&'a str>,
            private: bool,
            auto_init: bool,
        }

        #[derive(Deserialize)]
        struct Response {
            name: String,
            full_name: String,
            html_url: String,
            private: bool,
            description: Option<String>,
        }

        let payload = Payload { name, description, private, auto_init: true };
        let url = match org_login {
            Some(login) if !login.is_empty() => format!("{GITHUB_API}/orgs/{login}/repos"),
            _ => format!("{GITHUB_API}/user/repos"),
        };

        let result: Response = self.post_json(url, &payload).await.map_err(|e| {
            let msg = e.to_string();
            if msg.contains("403") && msg.contains("Resource not accessible by integration") {
                AppError::Provider("The GitHub App does not have permission to create repositories. If you recently added Administration permissions to the app, each organization must approve the updated permissions.".to_string())
            } else if msg.contains("422") {
                AppError::Provider("Repository name is already taken or invalid. Please choose a different name.".to_string())
            } else {
                e
            }
        })?;

        Ok(CreatedRepo {
            name: result.name,
            full_name: result.full_name,
            html_url: result.html_url,
            private: result.private,
            description: result.description,
        })
    }

    pub(super) async fn delete_repository_impl(&self, owner: &str, repo_name: &str) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repo_name}");
        self.delete(url).await.map_err(|e| {
            let msg = e.to_string();
            if msg.contains("403") {
                AppError::Provider("Permission denied. Make sure the GitHub App has Administration write permission.".to_string())
            } else if msg.contains("404") {
                AppError::Provider("Repository not found on GitHub.".to_string())
            } else {
                e
            }
        })
    }
}
