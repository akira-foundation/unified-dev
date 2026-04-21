use async_trait::async_trait;
use serde::Deserialize;

use crate::app::concerns::{ProviderDriverFactory, VcsProvider};
use crate::providers::dto::{CreatedRepo, ProviderOrg, ProviderRepo, VcsBranch, VcsCiCheck, VcsCiCheckStep, VcsPrComment, VcsPrFile, VcsPullRequest, VcsIssue};
use crate::providers::enums::{ProviderAuth, ProviderKind, ProviderOrgKind, PrMergeStrategy, PrReviewEvent, PullRequestState};
use crate::app::support::error::{AppError, AppResult};

use super::client::{GitHubDriver, GITHUB_API};
use super::types::{
    github_issue_to_vcs, GitHubCheckRunsResponse, GitHubIssue,
    GitHubIssueComment, GitHubJobResponse, GitHubPrFile,
};

#[derive(Deserialize)]
struct InstallationRepositoriesResponse {
    repositories: Vec<InstallationRepository>,
}

#[derive(Deserialize, Clone)]
struct InstallationRepository {
    id: u64,
    name: String,
    owner: InstallationRepositoryOwner,
    private: bool,
    visibility: String,
    default_branch: Option<String>,
    fork: Option<bool>,
}

#[derive(Deserialize, Clone)]
struct InstallationRepositoryOwner {
    id: u64,
    login: String,
    #[serde(rename = "type")]
    kind: String,
}

async fn list_installation_repositories(driver: &GitHubDriver) -> AppResult<Vec<InstallationRepository>> {
    let mut page = 1;
    let mut repositories = Vec::new();

    loop {
        let response = driver
            .client
            .get(format!("{GITHUB_API}/installation/repositories?per_page=100&page={page}"))
            .bearer_auth(&driver.token)
            .header("Accept", "application/vnd.github+json")
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("GitHub installation repositories error: {status} {body}")));
        }

        let chunk: InstallationRepositoriesResponse = response.json().await?;
        let count = chunk.repositories.len();
        repositories.extend(chunk.repositories);

        if count < 100 {
            break;
        }

        page += 1;
    }

    Ok(repositories)
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

    async fn create(&self, auth: ProviderAuth) -> AppResult<std::sync::Arc<dyn VcsProvider>> {
        let token = match auth {
            ProviderAuth::PersonalAccessToken { token } => token,
            ProviderAuth::GitHubOAuth { access_token, .. } => access_token,
            ProviderAuth::GitHubApp { installation_token, .. } => installation_token,
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

    async fn validate_auth(&self) -> AppResult<()> {
        let url = format!("{GITHUB_API}/user");
        let _: serde_json::Value = self.get_json(url).await?;
        Ok(())
    }

    async fn list_organizations(&self) -> AppResult<Vec<ProviderOrg>> {
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

    async fn list_repositories(&self) -> AppResult<Vec<ProviderRepo>> {
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

    async fn list_organization_repositories(&self, organization: &str) -> AppResult<Vec<ProviderRepo>> {
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

    async fn create_repository(&self, org_login: Option<&str>, name: &str, description: Option<&str>, private: bool) -> AppResult<CreatedRepo> {
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

    async fn delete_repository(&self, owner: &str, repo_name: &str) -> AppResult<()> {
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

    async fn list_pull_requests(
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
            commits: CommitConnection,
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
                    let ci_status = pr.commits.nodes.into_iter().next()
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

    async fn get_pull_request_comments(
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

    async fn post_pull_request_comment(
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

    async fn submit_pull_request_review(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        event: PrReviewEvent,
        body: Option<&str>,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/pulls/{pr_number}/reviews");
        let event_str = match event {
            PrReviewEvent::Approve => "APPROVE",
            PrReviewEvent::RequestChanges => "REQUEST_CHANGES",
            PrReviewEvent::Comment => "COMMENT",
        };
        let mut payload = serde_json::json!({ "event": event_str });
        if let Some(b) = body {
            payload["body"] = serde_json::Value::String(b.to_string());
        }
        let _: serde_json::Value = self.post_json(url, &payload).await?;
        Ok(())
    }

    async fn merge_pull_request(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        strategy: PrMergeStrategy,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/pulls/{pr_number}/merge");
        let merge_method = match strategy {
            PrMergeStrategy::Merge => "merge",
            PrMergeStrategy::Squash => "squash",
            PrMergeStrategy::Rebase => "rebase",
        };
        let payload = serde_json::json!({ "merge_method": merge_method });
        self.put_json(url, &payload).await
    }

    async fn list_pull_request_files(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<Vec<VcsPrFile>> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/pulls/{pr_number}/files");
        let files: Vec<GitHubPrFile> = self.fetch_paginated(url).await?;

        Ok(files
            .into_iter()
            .map(|f| VcsPrFile {
                filename: f.filename,
                status: f.status,
                additions: f.additions,
                deletions: f.deletions,
                patch: f.patch,
            })
            .collect())
    }

    async fn list_pr_checks(
        &self,
        owner: &str,
        repository: &str,
        sha: &str,
    ) -> AppResult<Vec<VcsCiCheck>> {
        let url = format!(
            "{GITHUB_API}/repos/{owner}/{repository}/commits/{sha}/check-runs?per_page=100"
        );
        let resp: GitHubCheckRunsResponse = self.get_json(url).await?;

        let step_futures = resp.check_runs.iter().map(|r| {
            let job_url = format!("{GITHUB_API}/repos/{owner}/{repository}/actions/jobs/{}", r.id);
            self.get_json::<GitHubJobResponse>(job_url)
        });
        let step_results = futures_util::future::join_all(step_futures).await;

        Ok(resp
            .check_runs
            .into_iter()
            .zip(step_results)
            .map(|(r, steps_result)| {
                let steps = steps_result
                    .ok()
                    .and_then(|j| j.steps)
                    .unwrap_or_default()
                    .into_iter()
                    .map(|s| VcsCiCheckStep {
                        number: s.number,
                        name: s.name,
                        status: s.status,
                        conclusion: s.conclusion,
                        started_at: s.started_at,
                        completed_at: s.completed_at,
                    })
                    .collect();
                VcsCiCheck {
                    id: r.id,
                    name: r.name,
                    status: r.status,
                    conclusion: r.conclusion,
                    started_at: r.started_at,
                    completed_at: r.completed_at,
                    steps,
                }
            })
            .collect())
    }

    async fn get_job_logs(
        &self,
        owner: &str,
        repository: &str,
        job_id: u64,
    ) -> AppResult<String> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/actions/jobs/{job_id}/logs");
        let blob_url = self.get_redirect_url(url).await?;
        let response = reqwest::Client::builder()
            .user_agent("UnifiedDev/1.0")
            .build()?
            .get(blob_url)
            .send()
            .await?;
        if !response.status().is_success() {
            let status = response.status();
            let body = response.text().await.unwrap_or_default();
            return Err(AppError::Provider(format!("Logs fetch error: {status} {body}")));
        }
        Ok(response.text().await?)
    }

    async fn list_issues(
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

    async fn create_issue(
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

    async fn update_issue(
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

    async fn close_issue(
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

    async fn delete_issue(
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

    async fn list_branches(
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

    async fn create_branch(
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

    async fn delete_branch(
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
