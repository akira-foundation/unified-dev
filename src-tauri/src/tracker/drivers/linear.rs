use async_trait::async_trait;
use issue_provider_core::{
    CommentId, Comments, Cycles, IssueError, IssueId, Issues, Labels, Milestones, Projects, Teams,
    Users, Viewer,
};
use issue_provider_linear::{linear, LinearClient};

use crate::app::support::error::{AppError, AppResult};

use super::super::dto::{
    TrackerComment, TrackerIssue, TrackerIssueDraft, TrackerIssueFilter, TrackerIssuePatch,
    TrackerNamed, TrackerPage, TrackerPageRequest,
};
use super::super::map;
use super::super::tracker::Tracker;

pub struct LinearTracker {
    client: LinearClient,
}

impl LinearTracker {
    pub fn new(token: impl Into<String>) -> Self {
        Self {
            client: linear().token(token).build(),
        }
    }
}

fn provider_err(error: IssueError) -> AppError {
    AppError::Provider(error.to_string())
}

#[async_trait]
impl Tracker for LinearTracker {
    fn kind(&self) -> &'static str {
        "linear"
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
        page: TrackerPageRequest,
    ) -> AppResult<TrackerPage<TrackerNamed>> {
        let result = Milestones::list(&self.client, map::to_page_request(&page))
            .await
            .map_err(provider_err)?;
        Ok(map::map_page(result, map::map_milestone))
    }

    async fn list_teams(&self, page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>> {
        let result = Teams::list(&self.client, map::to_page_request(&page))
            .await
            .map_err(provider_err)?;
        Ok(map::map_page(result, map::map_team))
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

    async fn list_cycles(&self, page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>> {
        let result = Cycles::list(&self.client, map::to_page_request(&page))
            .await
            .map_err(provider_err)?;
        Ok(map::map_page(result, map::map_cycle))
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
