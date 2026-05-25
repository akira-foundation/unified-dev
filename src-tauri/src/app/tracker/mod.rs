use std::sync::Arc;

use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;
use crate::tracker::Tracker;
use crate::tracker::dto::{
    StatusCategory, TrackerIssue, TrackerIssueDraft, TrackerIssueFilter, TrackerIssuePatch,
    TrackerNamed, TrackerPageRequest,
};

fn category_to_str(category: StatusCategory) -> &'static str {
    match category {
        StatusCategory::Backlog => "backlog",
        StatusCategory::Unstarted => "unstarted",
        StatusCategory::Started => "started",
        StatusCategory::Completed => "completed",
        StatusCategory::Canceled => "canceled",
    }
}

fn category_from_str(value: &str) -> Option<StatusCategory> {
    match value {
        "backlog" => Some(StatusCategory::Backlog),
        "unstarted" => Some(StatusCategory::Unstarted),
        "started" => Some(StatusCategory::Started),
        "completed" => Some(StatusCategory::Completed),
        "canceled" => Some(StatusCategory::Canceled),
        _ => None,
    }
}

#[derive(sqlx::FromRow)]
struct ExternalIssueRow {
    id: String,
    identifier: Option<String>,
    title: String,
    description: Option<String>,
    url: Option<String>,
    status: String,
    category: Option<String>,
    project_id: Option<String>,
    milestone_id: Option<String>,
    team_id: Option<String>,
    assignee_id: Option<String>,
    author_id: Option<String>,
    labels: String,
    priority: Option<i64>,
    created_at: Option<String>,
    updated_at: String,
}

impl From<ExternalIssueRow> for TrackerIssue {
    fn from(row: ExternalIssueRow) -> Self {
        TrackerIssue {
            id: row.id,
            identifier: row.identifier,
            title: row.title,
            description: row.description,
            url: row.url,
            status: row.status,
            category: row.category.as_deref().and_then(category_from_str),
            project: row.project_id,
            milestone: row.milestone_id,
            team: row.team_id,
            assignee: row.assignee_id,
            author: row.author_id,
            labels: serde_json::from_str(&row.labels).unwrap_or_default(),
            priority: row.priority.map(|value| value as u8),
            created_at: row.created_at,
            updated_at: row.updated_at,
        }
    }
}

const ISSUE_COLUMNS: &str = "id, identifier, title, description, url, status, category, project_id, milestone_id, team_id, assignee_id, author_id, labels, priority, created_at, updated_at";

async fn resolve_tracker(state: &AppState, provider: &str) -> AppResult<Arc<dyn Tracker>> {
    let encrypted: Option<String> =
        sqlx::query_scalar("SELECT token_cipher FROM tracker_credentials WHERE provider = ?")
            .bind(provider)
            .fetch_optional(&state.db_pool)
            .await?;
    let encrypted =
        encrypted.ok_or_else(|| AppError::Provider(format!("tracker not connected: {provider}")))?;
    let token = state.token_cipher.decrypt(&encrypted)?;
    state.tracker_registry.build(provider, token)
}

pub async fn connect(state: &AppState, provider: String, token: String) -> AppResult<TrackerNamed> {
    if !state.tracker_registry.supports(&provider) {
        return Err(AppError::Provider(format!(
            "unsupported tracker: {provider}"
        )));
    }

    let tracker = state.tracker_registry.build(&provider, token.clone())?;
    let user = tracker.current_user().await?;

    let encrypted = state.token_cipher.encrypt(&token)?;
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "INSERT INTO tracker_credentials (provider, token_cipher, account_id, account_name, created_at, updated_at) \
         VALUES (?, ?, ?, ?, ?, ?) \
         ON CONFLICT(provider) DO UPDATE SET token_cipher = excluded.token_cipher, account_id = excluded.account_id, account_name = excluded.account_name, updated_at = excluded.updated_at",
    )
    .bind(&provider)
    .bind(&encrypted)
    .bind(&user.id)
    .bind(&user.name)
    .bind(&now)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;

    Ok(user)
}

pub async fn status(state: &AppState, provider: &str) -> AppResult<bool> {
    let found: Option<String> =
        sqlx::query_scalar("SELECT provider FROM tracker_credentials WHERE provider = ?")
            .bind(provider)
            .fetch_optional(&state.db_pool)
            .await?;
    Ok(found.is_some())
}

pub async fn sync(
    state: &AppState,
    provider: String,
    filter: TrackerIssueFilter,
) -> AppResult<usize> {
    let tracker = resolve_tracker(state, &provider).await?;
    let synced_at = chrono::Utc::now().to_rfc3339();

    let mut after: Option<String> = None;
    let mut count = 0usize;

    loop {
        let page = tracker
            .list_issues(
                filter.clone(),
                TrackerPageRequest {
                    after: after.clone(),
                    limit: Some(50),
                },
            )
            .await?;

        for issue in &page.items {
            upsert_issue(state, &provider, issue, &synced_at).await?;
            count += 1;
        }

        match page.next {
            Some(cursor) => after = Some(cursor),
            None => break,
        }
    }

    sqlx::query(
        "INSERT INTO tracker_sync_state (provider, cursor, last_synced_at) VALUES (?, NULL, ?) \
         ON CONFLICT(provider) DO UPDATE SET last_synced_at = excluded.last_synced_at",
    )
    .bind(&provider)
    .bind(&synced_at)
    .execute(&state.db_pool)
    .await?;

    Ok(count)
}

async fn upsert_issue(
    state: &AppState,
    provider: &str,
    issue: &TrackerIssue,
    synced_at: &str,
) -> AppResult<()> {
    let labels = serde_json::to_string(&issue.labels)?;
    let category = issue.category.map(category_to_str);

    sqlx::query(
        "INSERT INTO external_issues (id, provider, identifier, title, description, url, status, category, project_id, milestone_id, team_id, assignee_id, author_id, labels, priority, created_at, updated_at, synced_at) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
         ON CONFLICT(id) DO UPDATE SET provider = excluded.provider, identifier = excluded.identifier, title = excluded.title, description = excluded.description, url = excluded.url, status = excluded.status, category = excluded.category, project_id = excluded.project_id, milestone_id = excluded.milestone_id, team_id = excluded.team_id, assignee_id = excluded.assignee_id, author_id = excluded.author_id, labels = excluded.labels, priority = excluded.priority, created_at = excluded.created_at, updated_at = excluded.updated_at, synced_at = excluded.synced_at",
    )
    .bind(&issue.id)
    .bind(provider)
    .bind(&issue.identifier)
    .bind(&issue.title)
    .bind(&issue.description)
    .bind(&issue.url)
    .bind(&issue.status)
    .bind(category)
    .bind(&issue.project)
    .bind(&issue.milestone)
    .bind(&issue.team)
    .bind(&issue.assignee)
    .bind(&issue.author)
    .bind(&labels)
    .bind(issue.priority.map(|value| value as i64))
    .bind(&issue.created_at)
    .bind(&issue.updated_at)
    .bind(synced_at)
    .execute(&state.db_pool)
    .await?;

    Ok(())
}

pub async fn list(state: &AppState, provider: &str) -> AppResult<Vec<TrackerIssue>> {
    let query = format!(
        "SELECT {ISSUE_COLUMNS} FROM external_issues WHERE provider = ? ORDER BY updated_at DESC"
    );
    let rows = sqlx::query_as::<_, ExternalIssueRow>(&query)
        .bind(provider)
        .fetch_all(&state.db_pool)
        .await?;
    Ok(rows.into_iter().map(TrackerIssue::from).collect())
}

pub async fn get(state: &AppState, id: &str) -> AppResult<TrackerIssue> {
    let query = format!("SELECT {ISSUE_COLUMNS} FROM external_issues WHERE id = ?");
    let row = sqlx::query_as::<_, ExternalIssueRow>(&query)
        .bind(id)
        .fetch_optional(&state.db_pool)
        .await?
        .ok_or_else(|| AppError::Provider(format!("issue not found: {id}")))?;
    Ok(TrackerIssue::from(row))
}

pub async fn create(
    state: &AppState,
    provider: String,
    draft: TrackerIssueDraft,
) -> AppResult<TrackerIssue> {
    let tracker = resolve_tracker(state, &provider).await?;
    let issue = tracker.create_issue(draft).await?;
    let now = chrono::Utc::now().to_rfc3339();
    upsert_issue(state, &provider, &issue, &now).await?;
    Ok(issue)
}

pub async fn update(
    state: &AppState,
    provider: String,
    id: String,
    patch: TrackerIssuePatch,
) -> AppResult<TrackerIssue> {
    let tracker = resolve_tracker(state, &provider).await?;
    let issue = tracker.update_issue(&id, patch).await?;
    let now = chrono::Utc::now().to_rfc3339();
    upsert_issue(state, &provider, &issue, &now).await?;
    Ok(issue)
}

pub async fn close(state: &AppState, provider: String, id: String) -> AppResult<TrackerIssue> {
    let tracker = resolve_tracker(state, &provider).await?;
    let issue = tracker.close_issue(&id).await?;
    let now = chrono::Utc::now().to_rfc3339();
    upsert_issue(state, &provider, &issue, &now).await?;
    Ok(issue)
}

pub async fn delete(state: &AppState, provider: String, id: String) -> AppResult<()> {
    let tracker = resolve_tracker(state, &provider).await?;
    tracker.delete_issue(&id).await?;
    sqlx::query("DELETE FROM external_issues WHERE id = ?")
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn category_string_roundtrips() {
        for category in [
            StatusCategory::Backlog,
            StatusCategory::Unstarted,
            StatusCategory::Started,
            StatusCategory::Completed,
            StatusCategory::Canceled,
        ] {
            assert_eq!(category_from_str(category_to_str(category)), Some(category));
        }
        assert_eq!(category_from_str("nonsense"), None);
    }

    #[test]
    fn row_decodes_into_dto() {
        let row = ExternalIssueRow {
            id: "ISS-1".into(),
            identifier: Some("ENG-1".into()),
            title: "Fix".into(),
            description: None,
            url: None,
            status: "In Progress".into(),
            category: Some("started".into()),
            project_id: Some("PRJ-1".into()),
            milestone_id: None,
            team_id: Some("TEAM-1".into()),
            assignee_id: None,
            author_id: None,
            labels: "[\"L-1\",\"L-2\"]".into(),
            priority: Some(2),
            created_at: None,
            updated_at: "t1".into(),
        };

        let dto = TrackerIssue::from(row);

        assert_eq!(dto.id, "ISS-1");
        assert_eq!(dto.identifier.as_deref(), Some("ENG-1"));
        assert_eq!(dto.category, Some(StatusCategory::Started));
        assert_eq!(dto.team.as_deref(), Some("TEAM-1"));
        assert_eq!(dto.labels, vec!["L-1", "L-2"]);
        assert_eq!(dto.priority, Some(2));
    }
}
