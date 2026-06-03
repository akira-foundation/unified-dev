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
    pub(super) async fn submit_pull_request_review_impl(
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

    pub(super) async fn merge_pull_request_impl(
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

        let response = self
            .client
            .put(&url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .json(&payload)
            .send()
            .await?;

        let status = response.status();
        let body = response.text().await.unwrap_or_default();

        if !status.is_success() {
            let msg = serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|v| v.get("message").and_then(|m| m.as_str()).map(|s| s.to_string()))
                .unwrap_or_else(|| body.clone());
            return Err(crate::app::support::error::AppError::Provider(format!(
                "GitHub merge failed: {status} {msg}"
            )));
        }

        let parsed: serde_json::Value = serde_json::from_str(&body)
            .map_err(|e| crate::app::support::error::AppError::Provider(format!(
                "GitHub merge decode failed: {e} — body: {body}"
            )))?;

        let merged = parsed.get("merged").and_then(|v| v.as_bool()).unwrap_or(false);
        if !merged {
            let msg = parsed
                .get("message")
                .and_then(|m| m.as_str())
                .unwrap_or("merge not applied");
            return Err(crate::app::support::error::AppError::Provider(format!(
                "GitHub merge not applied: {msg}"
            )));
        }

        Ok(())
    }

    pub(super) async fn mark_pull_request_ready_for_review_impl(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
    ) -> AppResult<()> {
        #[derive(Deserialize)]
        struct PrNode {
            id: String,
        }
        #[derive(Deserialize)]
        struct PrRepo {
            #[serde(rename = "pullRequest")]
            pull_request: Option<PrNode>,
        }
        #[derive(Deserialize)]
        struct LookupData {
            repository: Option<PrRepo>,
        }

        let lookup = r#"
            query($owner: String!, $repo: String!, $number: Int!) {
                repository(owner: $owner, name: $repo) {
                    pullRequest(number: $number) { id }
                }
            }
        "#;
        let data: LookupData = self
            .graphql(
                lookup,
                serde_json::json!({
                    "owner": owner,
                    "repo": repository,
                    "number": pr_number as i64,
                }),
            )
            .await?;

        let node_id = data
            .repository
            .and_then(|r| r.pull_request)
            .map(|p| p.id)
            .ok_or_else(|| AppError::Provider("pull request node id not found".into()))?;

        #[derive(Deserialize)]
        struct MarkReadyData {
            #[serde(rename = "markPullRequestReadyForReview")]
            _mark: serde_json::Value,
        }
        let _: MarkReadyData = self
            .graphql(
                "mutation MarkReady($id: ID!) { markPullRequestReadyForReview(input: { pullRequestId: $id }) { clientMutationId } }",
                serde_json::json!({ "id": node_id }),
            )
            .await?;

        Ok(())
    }

    pub(super) async fn set_pull_request_state_impl(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        state: &str,
    ) -> AppResult<()> {
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/pulls/{pr_number}");
        let payload = serde_json::json!({ "state": state });
        let _: serde_json::Value = self.patch_json(url, &payload).await?;
        Ok(())
    }

    pub(super) async fn close_pull_request_impl(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        comment: Option<&str>,
    ) -> AppResult<()> {
        if let Some(body) = comment.map(str::trim).filter(|b| !b.is_empty()) {
            self.post_pull_request_comment_impl(owner, repository, pr_number, body).await?;
        }
        self.set_pull_request_state_impl(owner, repository, pr_number, "closed").await
    }

    pub(super) async fn list_repository_labels_impl(
        &self,
        owner: &str,
        repository: &str,
    ) -> AppResult<Vec<crate::providers::dto::VcsRepoLabel>> {
        #[derive(Deserialize)]
        struct GitHubLabel {
            name: String,
            color: String,
            description: Option<String>,
        }
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/labels");
        let labels: Vec<GitHubLabel> = self.fetch_paginated(url).await?;
        Ok(labels
            .into_iter()
            .map(|l| crate::providers::dto::VcsRepoLabel {
                name: l.name,
                color: l.color,
                description: l.description,
            })
            .collect())
    }

    pub(super) async fn create_repository_label_impl(
        &self,
        owner: &str,
        repository: &str,
        name: &str,
        color: Option<&str>,
        description: Option<&str>,
    ) -> AppResult<crate::providers::dto::VcsRepoLabel> {
        #[derive(Deserialize)]
        struct GitHubLabel {
            name: String,
            color: String,
            description: Option<String>,
        }
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/labels");
        let resolved_color = color.unwrap_or("ededed").trim_start_matches('#').to_string();
        let mut payload = serde_json::json!({ "name": name, "color": resolved_color });
        if let Some(d) = description {
            payload["description"] = serde_json::Value::String(d.to_string());
        }
        let created: GitHubLabel = self.post_json(url, &payload).await?;
        Ok(crate::providers::dto::VcsRepoLabel {
            name: created.name,
            color: created.color,
            description: created.description,
        })
    }

    pub(super) async fn set_pull_request_labels_impl(
        &self,
        owner: &str,
        repository: &str,
        pr_number: u64,
        labels: Vec<String>,
    ) -> AppResult<Vec<String>> {
        #[derive(Deserialize)]
        struct GitHubLabelResponse {
            name: String,
        }
        let url = format!("{GITHUB_API}/repos/{owner}/{repository}/issues/{pr_number}/labels");
        let payload = serde_json::json!({ "labels": labels });
        let response = self
            .client
            .put(&url)
            .bearer_auth(&self.token)
            .header("Accept", "application/vnd.github+json")
            .json(&payload)
            .send()
            .await?;

        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        if !status.is_success() {
            let msg = serde_json::from_str::<serde_json::Value>(&body)
                .ok()
                .and_then(|v| v.get("message").and_then(|m| m.as_str()).map(|s| s.to_string()))
                .unwrap_or_else(|| body.clone());
            return Err(AppError::Provider(format!(
                "GitHub set labels failed: {status} {msg}"
            )));
        }

        let parsed: Vec<GitHubLabelResponse> = serde_json::from_str(&body)
            .map_err(|e| AppError::Provider(format!("GitHub set labels decode failed: {e} — body: {body}")))?;
        Ok(parsed.into_iter().map(|l| l.name).collect())
    }

    pub(super) async fn list_pull_request_files_impl(
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

    pub(super) async fn list_pr_checks_impl(
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

    pub(super) async fn get_job_logs_impl(
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
}
