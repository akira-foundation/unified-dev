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
    pub(super) async fn list_organizations_impl(&self) -> AppResult<Vec<ProviderOrg>> {
        if let Ok(repositories) = list_installation_repositories(self).await {
            let mut results: Vec<ProviderOrg> = Vec::new();
            for repo in repositories {
                let kind = if repo.owner.kind == "Organization" {
                    ProviderOrgKind::Organization
                } else {
                    ProviderOrgKind::Personal
                };

                if results.iter().any(|org| org.login == repo.owner.login) {
                    continue;
                }

                results.push(ProviderOrg {
                    id: repo.owner.id.to_string(),
                    login: repo.owner.login,
                    kind,
                    app_installed: None,
                    app_install_url: None,
                    app_manage_url: None,
                });
            }

            results.sort_by(|a, b| a.login.cmp(&b.login));

            return Ok(results);
        }

        #[derive(Deserialize)]
        struct Data {
            viewer: Viewer,
        }
        #[derive(Deserialize)]
        struct Viewer {
            id: String,
            login: String,
            organizations: OrgConnection,
        }
        #[derive(Deserialize)]
        struct OrgConnection {
            nodes: Vec<OrgNode>,
        }
        #[derive(Deserialize)]
        struct OrgNode {
            #[serde(rename = "databaseId")]
            database_id: u64,
            login: String,
        }

        let query = r#"
            query {
                viewer {
                    id
                    login
                    organizations(first: 100) {
                        nodes { databaseId login }
                    }
                }
            }
        "#;

        let data: Data = self.graphql(query, serde_json::json!({})).await?;

        let mut results = Vec::new();
        results.push(ProviderOrg {
            id: data.viewer.id,
            login: data.viewer.login,
            kind: ProviderOrgKind::Personal,
            app_installed: None,
            app_install_url: None,
            app_manage_url: None,
        });
        results.extend(data.viewer.organizations.nodes.into_iter().map(|org| ProviderOrg {
            id: org.database_id.to_string(),
            login: org.login,
            kind: ProviderOrgKind::Organization,
            app_installed: None,
            app_install_url: None,
            app_manage_url: None,
        }));

        Ok(results)
    }

    pub(super) async fn list_repositories_impl(&self) -> AppResult<Vec<ProviderRepo>> {
        if let Ok(repositories) = list_installation_repositories(self).await {
            let mut repos = repositories
                .into_iter()
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

            repos.sort_by(|a, b| a.owner.cmp(&b.owner).then(a.name.cmp(&b.name)));

            return Ok(repos);
        }

        #[derive(Deserialize)]
        struct Data {
            viewer: Viewer,
        }
        #[derive(Deserialize)]
        struct Viewer {
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
            query($after: String) {
                viewer {
                    repositories(first: 100, after: $after, affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER]) {
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

        let repos = self.graphql_paginated::<ProviderRepo, _, Data>(
            query,
            serde_json::json!({}),
            |data| {
                let conn = data.viewer.repositories;
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
}
