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
