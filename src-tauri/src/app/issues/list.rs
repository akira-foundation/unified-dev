use sqlx::SqlitePool;
use tauri::State;

use crate::database::records::IssueRecord;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn list(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<IssueDto>, String> {
    list_with_pool(
        &state.pool().await.map_err(|e| e.to_string())?,
        &org_id,
        &repo_name,
        scope.as_deref(),
        current_login.as_deref(),
    )
    .await
}

pub async fn list_with_pool(
    pool: &SqlitePool,
    org_id: &str,
    repo_name: &str,
    scope: Option<&str>,
    current_login: Option<&str>,
) -> Result<Vec<IssueDto>, String> {
    let records = sqlx::query_as::<_, IssueRecord>(
        "SELECT * FROM issues WHERE org_id = ? AND repo_name = ? ORDER BY number DESC",
    )
    .bind(org_id)
    .bind(repo_name)
    .fetch_all(pool)
    .await
    .map_err(|e| e.to_string())?;

    let issues: Vec<IssueDto> = records
        .into_iter()
        .map(super::to_dto::record_to_dto)
        .collect();
    Ok(filter_by_scope(
        issues,
        scope.unwrap_or("my_queue"),
        current_login,
    ))
}

pub fn filter_by_scope(
    issues: Vec<IssueDto>,
    scope: &str,
    current_login: Option<&str>,
) -> Vec<IssueDto> {
    let login = current_login.map(|v| v.to_lowercase());
    issues
        .into_iter()
        .filter(|issue| match scope {
            "all" => true,
            "all_open" => issue.status == "open",
            _ => {
                if issue.status != "open" {
                    return false;
                }
                if !issue.sync_with_provider {
                    return true;
                }
                if issue.assignees.is_empty() {
                    return true;
                }
                login
                    .as_ref()
                    .map(|current| issue.assignees.iter().any(|a| a.to_lowercase() == *current))
                    .unwrap_or(false)
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_utils::{seed_organization, seed_provider, setup_test_db};

    fn make_issue(status: &str, sync: bool, assignees: Vec<&str>) -> IssueDto {
        IssueDto {
            id: format!("id-{status}"),
            external_id: "ext".into(),
            provider: "github".into(),
            org_id: "org".into(),
            repo_name: "repo".into(),
            number: 1,
            title: "t".into(),
            body: None,
            status: status.into(),
            state_reason: None,
            labels: vec![],
            label_colors: vec![],
            assignees: assignees.into_iter().map(String::from).collect(),
            author: None,
            url: "u".into(),
            linked_pr_numbers: vec![],
            created_at: "c".into(),
            updated_at: "u".into(),
            synced_at: "s".into(),
            sync_with_provider: sync,
        }
    }

    #[test]
    fn scope_all_returns_everything() {
        let issues = vec![
            make_issue("open", true, vec!["alice"]),
            make_issue("closed", true, vec!["alice"]),
        ];
        let out = filter_by_scope(issues, "all", Some("bob"));
        assert_eq!(out.len(), 2);
    }

    #[test]
    fn scope_all_open_excludes_closed() {
        let issues = vec![
            make_issue("open", true, vec!["alice"]),
            make_issue("closed", true, vec!["alice"]),
        ];
        let out = filter_by_scope(issues, "all_open", Some("bob"));
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].status, "open");
    }

    #[test]
    fn scope_my_queue_keeps_local_only_issues() {
        let mut local = make_issue("open", false, vec![]);
        local.id = "local".into();
        let mine = make_issue("open", true, vec!["bob"]);
        let other = make_issue("open", true, vec!["alice"]);
        let out = filter_by_scope(vec![local, mine, other], "my_queue", Some("bob"));
        assert_eq!(out.len(), 2);
        assert!(out.iter().any(|i| i.id == "local"));
        assert!(out.iter().all(|i| i.status == "open"));
        assert!(!out.iter().any(|i| i.assignees.iter().any(|a| a == "alice")));
    }

    #[test]
    fn scope_my_queue_includes_unassigned_synced_issues() {
        let issues = vec![make_issue("open", true, vec![])];
        let out = filter_by_scope(issues, "my_queue", Some("bob"));
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn scope_my_queue_drops_when_login_missing() {
        let issues = vec![make_issue("open", true, vec!["bob"])];
        let out = filter_by_scope(issues, "my_queue", None);
        assert!(out.is_empty(), "without a login we can't match assignees");
    }

    #[tokio::test]
    async fn list_with_pool_reads_issues_for_repo() {
        let pool = setup_test_db().await;
        seed_provider(&pool, "p1", "github").await;
        seed_organization(&pool, "o1", "p1").await;

        for (num, status) in [(1, "open"), (2, "closed"), (3, "open")] {
            sqlx::query(
                "INSERT INTO issues
                    (id, external_id, provider, org_id, repo_name, number, title,
                     status, labels, assignees, url, linked_pr_numbers,
                     created_at, updated_at, synced_at)
                 VALUES (?, ?, 'github', 'o1', 'r1', ?, ?, ?, '[]', '[]', ?, '[]',
                         'now', 'now', 'now')",
            )
            .bind(format!("id-{num}"))
            .bind(format!("ext-{num}"))
            .bind(num as i64)
            .bind(format!("issue-{num}"))
            .bind(status)
            .bind(format!("https://example.com/{num}"))
            .execute(&pool)
            .await
            .unwrap();
        }

        let all = list_with_pool(&pool, "o1", "r1", Some("all"), None)
            .await
            .unwrap();
        assert_eq!(all.len(), 3, "scope=all returns every row");

        let open = list_with_pool(&pool, "o1", "r1", Some("all_open"), None)
            .await
            .unwrap();
        assert_eq!(open.len(), 2);
        assert!(open.iter().all(|i| i.status == "open"));

        let other_repo = list_with_pool(&pool, "o1", "missing", Some("all"), None)
            .await
            .unwrap();
        assert!(other_repo.is_empty(), "repo filter must isolate results");
    }
}
