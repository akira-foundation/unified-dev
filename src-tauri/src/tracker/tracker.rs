use async_trait::async_trait;

use crate::app::support::error::AppResult;

use super::dto::{
    TrackerComment, TrackerIssue, TrackerIssueDraft, TrackerIssueFilter, TrackerIssuePatch,
    TrackerNamed, TrackerPage, TrackerPageRequest,
};

#[async_trait]
#[allow(dead_code)]
pub trait Tracker: Send + Sync {
    fn kind(&self) -> &'static str;

    async fn current_user(&self) -> AppResult<TrackerNamed>;

    async fn list_issues(
        &self,
        filter: TrackerIssueFilter,
        page: TrackerPageRequest,
    ) -> AppResult<TrackerPage<TrackerIssue>>;

    async fn get_issue(&self, id: &str) -> AppResult<TrackerIssue>;

    async fn create_issue(&self, draft: TrackerIssueDraft) -> AppResult<TrackerIssue>;

    async fn update_issue(&self, id: &str, patch: TrackerIssuePatch) -> AppResult<TrackerIssue>;

    async fn close_issue(&self, id: &str) -> AppResult<TrackerIssue>;

    async fn delete_issue(&self, id: &str) -> AppResult<()>;

    async fn list_projects(&self, page: TrackerPageRequest)
        -> AppResult<TrackerPage<TrackerNamed>>;

    async fn list_milestones(
        &self,
        page: TrackerPageRequest,
    ) -> AppResult<TrackerPage<TrackerNamed>>;

    async fn list_teams(&self, page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>>;

    async fn list_users(&self, page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>>;

    async fn list_labels(&self, page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>>;

    async fn list_cycles(&self, page: TrackerPageRequest) -> AppResult<TrackerPage<TrackerNamed>>;

    async fn list_comments(
        &self,
        issue: &str,
        page: TrackerPageRequest,
    ) -> AppResult<TrackerPage<TrackerComment>>;

    async fn post_comment(&self, issue: &str, body: String) -> AppResult<TrackerComment>;

    async fn delete_comment(&self, id: &str) -> AppResult<()>;
}
