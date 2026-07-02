use std::collections::HashMap;
use std::future::Future;
use std::sync::Arc;

use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;
use crate::tracker::dto::{
    StatusCategory, TrackerIssue, TrackerIssueDraft, TrackerIssueFilter, TrackerIssuePatch,
    TrackerNamed, TrackerPageRequest,
};
use crate::tracker::Tracker;

pub mod jira_oauth;

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
    project_name: Option<String>,
    milestone_name: Option<String>,
    team_name: Option<String>,
    assignee_name: Option<String>,
    author_name: Option<String>,
    label_names: String,
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
            project_name: row.project_name,
            milestone_name: row.milestone_name,
            team_name: row.team_name,
            assignee_name: row.assignee_name,
            author_name: row.author_name,
            label_names: serde_json::from_str(&row.label_names).unwrap_or_default(),
        }
    }
}

const ISSUE_COLUMNS: &str = "id, identifier, title, description, url, status, category, project_id, milestone_id, team_id, assignee_id, author_id, labels, priority, created_at, updated_at, project_name, milestone_name, team_name, assignee_name, author_name, label_names";

async fn resolve_tracker(state: &AppState, provider: &str) -> AppResult<Arc<dyn Tracker>> {
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    let encrypted: Option<String> = sqlx::query_scalar(
        "SELECT token_cipher FROM tracker_credentials WHERE provider = ? AND customer_id = ?",
    )
    .bind(provider)
    .bind(customer_id)
    .fetch_optional(&state.pool().await?)
    .await?;
    let encrypted = encrypted
        .ok_or_else(|| AppError::Provider(format!("tracker not connected: {provider}")))?;
    let token = state.token_cipher.decrypt(&encrypted)?;
    let token = if provider == "jira" {
        jira_oauth::ensure_fresh(state, token).await?
    } else {
        token
    };
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
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    sqlx::query(
        "INSERT INTO tracker_credentials (provider, token_cipher, account_id, account_name, created_at, updated_at, customer_id) \
         VALUES (?, ?, ?, ?, ?, ?, ?) \
         ON CONFLICT(provider) DO UPDATE SET token_cipher = excluded.token_cipher, account_id = excluded.account_id, account_name = excluded.account_name, updated_at = excluded.updated_at, customer_id = excluded.customer_id",
    )
    .bind(&provider)
    .bind(&encrypted)
    .bind(&user.id)
    .bind(&user.name)
    .bind(&now)
    .bind(&now)
    .bind(&customer_id)
    .execute(&state.pool().await?)
    .await?;

    Ok(user)
}

pub fn providers(state: &AppState) -> Vec<String> {
    state.tracker_registry.providers()
}

pub async fn disconnect(state: &AppState, provider: &str) -> AppResult<()> {
    sqlx::query("DELETE FROM tracker_credentials WHERE provider = ?")
        .bind(provider)
        .execute(&state.pool().await?)
        .await?;
    sqlx::query("DELETE FROM external_issues WHERE provider = ?")
        .bind(provider)
        .execute(&state.pool().await?)
        .await?;
    sqlx::query("DELETE FROM tracker_sync_state WHERE provider = ?")
        .bind(provider)
        .execute(&state.pool().await?)
        .await?;
    Ok(())
}

pub async fn status(state: &AppState, provider: &str) -> AppResult<bool> {
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    let found: Option<String> = sqlx::query_scalar(
        "SELECT provider FROM tracker_credentials WHERE provider = ? AND customer_id = ?",
    )
    .bind(provider)
    .bind(customer_id)
    .fetch_optional(&state.pool().await?)
    .await?;
    Ok(found.is_some())
}

#[derive(Default)]
struct NameMaps {
    projects: HashMap<String, String>,
    milestones: HashMap<String, String>,
    teams: HashMap<String, String>,
    users: HashMap<String, String>,
    labels: HashMap<String, String>,
}

async fn collect_named<F, Fut>(mut fetch: F) -> AppResult<HashMap<String, String>>
where
    F: FnMut(TrackerPageRequest) -> Fut,
    Fut: Future<Output = AppResult<crate::tracker::dto::TrackerPage<TrackerNamed>>>,
{
    let mut map = HashMap::new();
    let mut after: Option<String> = None;
    loop {
        let page = fetch(TrackerPageRequest {
            after: after.clone(),
            limit: Some(100),
        })
        .await?;
        for named in page.items {
            map.insert(named.id, named.name);
        }
        match page.next {
            Some(cursor) => after = Some(cursor),
            None => break,
        }
    }
    Ok(map)
}

async fn fetch_name_maps(tracker: &Arc<dyn Tracker>) -> AppResult<NameMaps> {
    Ok(NameMaps {
        projects: collect_named(|page| tracker.list_projects(page)).await?,
        milestones: collect_named(|page| tracker.list_milestones(page)).await?,
        teams: collect_named(|page| tracker.list_teams(page)).await?,
        users: collect_named(|page| tracker.list_users(page)).await?,
        labels: collect_named(|page| tracker.list_labels(page)).await?,
    })
}

async fn collect_all<F, Fut>(mut fetch: F) -> AppResult<Vec<TrackerNamed>>
where
    F: FnMut(TrackerPageRequest) -> Fut,
    Fut: Future<Output = AppResult<crate::tracker::dto::TrackerPage<TrackerNamed>>>,
{
    let mut items = Vec::new();
    let mut after: Option<String> = None;
    loop {
        let page = fetch(TrackerPageRequest {
            after: after.clone(),
            limit: Some(100),
        })
        .await?;
        items.extend(page.items);
        match page.next {
            Some(cursor) => after = Some(cursor),
            None => break,
        }
    }
    Ok(items)
}

pub async fn list_projects_named(state: &AppState, provider: &str) -> AppResult<Vec<TrackerNamed>> {
    let tracker = resolve_tracker(state, provider).await?;
    collect_all(|page| tracker.list_projects(page)).await
}

pub async fn list_teams_named(state: &AppState, provider: &str) -> AppResult<Vec<TrackerNamed>> {
    let tracker = resolve_tracker(state, provider).await?;
    collect_all(|page| tracker.list_teams(page)).await
}

fn resolve_names(issue: &TrackerIssue, maps: &NameMaps) -> TrackerIssue {
    let mut out = issue.clone();
    out.project_name = issue
        .project
        .as_ref()
        .and_then(|id| maps.projects.get(id).cloned());
    out.milestone_name = issue
        .milestone
        .as_ref()
        .and_then(|id| maps.milestones.get(id).cloned());
    out.team_name = issue
        .team
        .as_ref()
        .and_then(|id| maps.teams.get(id).cloned());
    out.assignee_name = issue
        .assignee
        .as_ref()
        .and_then(|id| maps.users.get(id).cloned());
    out.author_name = issue
        .author
        .as_ref()
        .and_then(|id| maps.users.get(id).cloned());
    out.label_names = issue
        .labels
        .iter()
        .map(|id| maps.labels.get(id).cloned().unwrap_or_else(|| id.clone()))
        .collect();
    out
}

pub async fn sync(
    state: &AppState,
    provider: String,
    filter: TrackerIssueFilter,
) -> AppResult<usize> {
    let tracker = resolve_tracker(state, &provider).await?;
    let synced_at = chrono::Utc::now().to_rfc3339();
    let maps = fetch_name_maps(&tracker).await?;

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
            let resolved = resolve_names(issue, &maps);
            upsert_issue(state, &provider, &resolved, &synced_at).await?;
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
    .execute(&state.pool().await?)
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
    let label_names = serde_json::to_string(&issue.label_names)?;
    let category = issue.category.map(category_to_str);

    sqlx::query(
        "INSERT INTO external_issues (id, provider, identifier, title, description, url, status, category, project_id, milestone_id, team_id, assignee_id, author_id, labels, priority, created_at, updated_at, synced_at, project_name, milestone_name, team_name, assignee_name, author_name, label_names) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) \
         ON CONFLICT(id) DO UPDATE SET provider = excluded.provider, identifier = excluded.identifier, title = excluded.title, description = excluded.description, url = excluded.url, status = excluded.status, category = excluded.category, project_id = excluded.project_id, milestone_id = excluded.milestone_id, team_id = excluded.team_id, assignee_id = excluded.assignee_id, author_id = excluded.author_id, labels = excluded.labels, priority = excluded.priority, created_at = excluded.created_at, updated_at = excluded.updated_at, synced_at = excluded.synced_at, \
         project_name = COALESCE(excluded.project_name, external_issues.project_name), \
         milestone_name = COALESCE(excluded.milestone_name, external_issues.milestone_name), \
         team_name = COALESCE(excluded.team_name, external_issues.team_name), \
         assignee_name = COALESCE(excluded.assignee_name, external_issues.assignee_name), \
         author_name = COALESCE(excluded.author_name, external_issues.author_name), \
         label_names = COALESCE(NULLIF(excluded.label_names, '[]'), external_issues.label_names)",
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
    .bind(&issue.project_name)
    .bind(&issue.milestone_name)
    .bind(&issue.team_name)
    .bind(&issue.assignee_name)
    .bind(&issue.author_name)
    .bind(&label_names)
    .execute(&state.pool().await?)
    .await?;

    Ok(())
}

pub async fn list(state: &AppState, provider: &str) -> AppResult<Vec<TrackerIssue>> {
    let query = format!(
        "SELECT {ISSUE_COLUMNS} FROM external_issues WHERE provider = ? ORDER BY updated_at DESC"
    );
    let rows = sqlx::query_as::<_, ExternalIssueRow>(&query)
        .bind(provider)
        .fetch_all(&state.pool().await?)
        .await?;
    Ok(rows.into_iter().map(TrackerIssue::from).collect())
}

pub async fn get(state: &AppState, id: &str) -> AppResult<TrackerIssue> {
    let query = format!("SELECT {ISSUE_COLUMNS} FROM external_issues WHERE id = ?");
    let row = sqlx::query_as::<_, ExternalIssueRow>(&query)
        .bind(id)
        .fetch_optional(&state.pool().await?)
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
        .execute(&state.pool().await?)
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
            project_name: Some("Mobile".into()),
            milestone_name: None,
            team_name: Some("Engineering".into()),
            assignee_name: None,
            author_name: None,
            label_names: "[\"Bug\",\"P1\"]".into(),
        };

        let dto = TrackerIssue::from(row);

        assert_eq!(dto.id, "ISS-1");
        assert_eq!(dto.identifier.as_deref(), Some("ENG-1"));
        assert_eq!(dto.category, Some(StatusCategory::Started));
        assert_eq!(dto.team.as_deref(), Some("TEAM-1"));
        assert_eq!(dto.labels, vec!["L-1", "L-2"]);
        assert_eq!(dto.priority, Some(2));
        assert_eq!(dto.project_name.as_deref(), Some("Mobile"));
        assert_eq!(dto.team_name.as_deref(), Some("Engineering"));
        assert_eq!(dto.label_names, vec!["Bug", "P1"]);
    }
}
