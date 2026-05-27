use async_trait::async_trait;
use issue_provider_core::{
    CommentId, Comments, ErrorKind, IssueError, IssueId, Issues, Labels, Projects, Users, Viewer,
};
use issue_provider_jira::{jira, JiraClient};
use serde::{Deserialize, Serialize};

use crate::app::support::error::{AppError, AppResult};

use super::super::dto::{
    TrackerComment, TrackerIssue, TrackerIssueDraft, TrackerIssueFilter, TrackerIssuePatch,
    TrackerNamed, TrackerPage, TrackerPageRequest,
};
use super::super::map;
use super::super::tracker::Tracker;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct JiraOauthBundle {
    pub cloud_id: String,
    pub access_token: String,
    #[serde(default)]
    pub refresh_token: Option<String>,
    #[serde(default)]
    pub expires_at: Option<String>,
}

pub struct JiraTracker {
    client: JiraClient,
}

impl JiraTracker {
    pub fn new(credentials: impl Into<String>) -> AppResult<Self> {
        let bundle: JiraOauthBundle = serde_json::from_str(&credentials.into())
            .map_err(|_| AppError::Provider("invalid jira oauth credentials".to_string()))?;
        Ok(Self {
            client: jira().bearer(bundle.cloud_id, bundle.access_token).build(),
        })
    }
}

fn provider_err(error: IssueError) -> AppError {
    let message = match error.kind() {
        ErrorKind::Unauthorized => {
            "Unauthorized. Check your Jira email and API token.".to_string()
        }
        ErrorKind::RateLimited => "Jira rate limit reached. Try again in a moment.".to_string(),
        ErrorKind::NotFound => "Not found on Jira.".to_string(),
        ErrorKind::Transport | ErrorKind::TransportNotConfigured => {
            let detail = error.message().trim();
            if detail.is_empty() {
                "Could not reach Jira. Check your connection and site URL.".to_string()
            } else {
                format!("Could not reach Jira: {detail}")
            }
        }
        ErrorKind::Decode => "Unexpected response from Jira.".to_string(),
        ErrorKind::Provider => {
            let detail = error.message().trim();
            if detail.is_empty() {
                "Jira request failed.".to_string()
            } else {
                detail.to_string()
            }
        }
    };
    AppError::Provider(message)
}

fn empty_page() -> TrackerPage<TrackerNamed> {
    TrackerPage {
        items: Vec::new(),
        next: None,
    }
}

#[async_trait]
impl Tracker for JiraTracker {
    fn kind(&self) -> &'static str {
        "jira"
    }

    async fn current_user(&self) -> AppResult<TrackerNamed> {
        let user = Viewer::current_user(&self.client)
            .await
            .map_err(provider_err)?;
        Ok(map::map_user(&user))
    }

    async fn list_issues(
        &self,
        filter: TrackerIssueFilter,
        page: TrackerPageRequest,
    ) -> AppResult<TrackerPage<TrackerIssue>> {
        let result = Issues::list(
            &self.client,
            map::to_filter(&filter),
            map::to_page_request(&page),
        )
        .await
        .map_err(provider_err)?;
        Ok(map::map_page(result, map::map_issue))
    }

    async fn get_issue(&self, id: &str) -> AppResult<TrackerIssue> {
        let issue = Issues::get(&self.client, IssueId::make(id))
            .await
            .map_err(provider_err)?;
        Ok(map::map_issue(&issue))
    }

    async fn create_issue(&self, draft: TrackerIssueDraft) -> AppResult<TrackerIssue> {
        let issue = Issues::create(&self.client, map::to_draft(draft))
            .await
            .map_err(provider_err)?;
        Ok(map::map_issue(&issue))
    }

    async fn update_issue(&self, id: &str, patch: TrackerIssuePatch) -> AppResult<TrackerIssue> {
        let issue = Issues::update(&self.client, IssueId::make(id), map::to_patch(patch))
            .await
            .map_err(provider_err)?;
        Ok(map::map_issue(&issue))
    }

    async fn close_issue(&self, id: &str) -> AppResult<TrackerIssue> {
        let issue = Issues::close(&self.client, IssueId::make(id))
            .await
            .map_err(provider_err)?;
        Ok(map::map_issue(&issue))
    }

    async fn delete_issue(&self, id: &str) -> AppResult<()> {
        Issues::delete(&self.client, IssueId::make(id))
            .await
            .map_err(provider_err)
    }

    async fn list_projects(
        &self,
        page: TrackerPageRequest,
    ) -> AppResult<TrackerPage<TrackerNamed>> {
        let result = Projects::list(&self.client, map::to_page_request(&page))
            .await
            .map_err(provider_err)?;
        Ok(map::map_page(result, map::map_project))
    }

    async fn list_milestones(
        &self,
        _page: TrackerPageRequest,
    ) -> AppResult<TrackerPage<TrackerNamed>> {
        Ok(empty_page())
    }

    async fn list_teams(&self, _page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>> {
        Ok(empty_page())
    }

    async fn list_users(&self, page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>> {
        let result = Users::list(&self.client, map::to_page_request(&page))
            .await
            .map_err(provider_err)?;
        Ok(map::map_page(result, map::map_user))
    }

    async fn list_labels(&self, page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>> {
        let result = Labels::list(&self.client, map::to_page_request(&page))
            .await
            .map_err(provider_err)?;
        Ok(map::map_page(result, map::map_label))
    }

    async fn list_cycles(&self, _page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>> {
        Ok(empty_page())
    }

    async fn list_comments(
        &self,
        issue: &str,
        page: TrackerPageRequest,
    ) -> AppResult<TrackerPage<TrackerComment>> {
        let result = Comments::list_comments(
            &self.client,
            IssueId::make(issue),
            map::to_page_request(&page),
        )
        .await
        .map_err(provider_err)?;
        Ok(map::map_page(result, map::map_comment))
    }

    async fn post_comment(&self, issue: &str, body: String) -> AppResult<TrackerComment> {
        let comment = Comments::post_comment(&self.client, IssueId::make(issue), body)
            .await
            .map_err(provider_err)?;
        Ok(map::map_comment(&comment))
    }

    async fn delete_comment(&self, id: &str) -> AppResult<()> {
        Comments::delete_comment(&self.client, CommentId::make(id))
            .await
            .map_err(provider_err)
    }
}
