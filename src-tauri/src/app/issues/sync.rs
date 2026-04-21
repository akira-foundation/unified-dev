use tauri::State;
use std::collections::HashSet;

use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn sync(
    state: State<'_, AppState>,
    org_id: String,
    owner: String,
    repo_name: String,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<IssueDto>, String> {
    let scope = scope.unwrap_or_else(|| "my_queue".to_string());
    let state_param = match scope.as_str() {
        "all" => Some("all"),
        _ => Some("open"),
    };

    let (effective_owner, effective_repo) = resolve_upstream(&state, &org_id, &owner, &repo_name).await;

    let (provider, _) = crate::app::orgs::resolve_provider::resolve_provider_for_repo_owner(
        &state,
        &org_id,
        &effective_owner,
    )
    .await?;
    let provider_kind = provider.kind().to_string();

    let issues = provider
        .list_issues(&effective_owner, &effective_repo, state_param)
        .await
        .map_err(|e| e.to_string())?;

    let login = current_login.clone().map(|value| value.to_lowercase());
    let filtered_issues = issues
        .into_iter()
        .filter(|issue| match scope.as_str() {
            "all" => true,
            "all_open" => issue.status == "open",
            _ => {
                if issue.status != "open" {
                    return false;
                }

                if issue.assignees.is_empty() {
                    return true;
                }

                login.as_ref().map(|current| {
                    issue.assignees.iter().any(|assignee| assignee.to_lowercase() == *current)
                }).unwrap_or(false)
            }
        })
        .collect::<Vec<_>>();

    if scope == "all" {
        let remote_numbers: HashSet<i64> = filtered_issues.iter().map(|issue| issue.number as i64).collect();

        let local_numbers: Vec<i64> = sqlx::query_scalar::<_, i64>(
            "SELECT number FROM issues WHERE org_id = ? AND repo_name = ? AND sync_with_provider = 1",
        )
        .bind(&org_id)
        .bind(&repo_name)
        .fetch_all(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

        for local_number in local_numbers {
            if !remote_numbers.contains(&local_number) {
                sqlx::query("DELETE FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?")
                    .bind(&org_id)
                    .bind(&repo_name)
                    .bind(local_number)
                    .execute(&state.db_pool)
                    .await
                    .map_err(|e| e.to_string())?;
            }
        }
    }

    let now = chrono::Utc::now().to_rfc3339();

    for issue in &filtered_issues {
        let id = format!("{org_id}:{provider_kind}:{repo_name}:{}", issue.number);
        let labels_json = serde_json::to_string(&issue.labels).unwrap_or_else(|_| "[]".to_string());
        let label_colors_json = serde_json::to_string(&issue.label_colors).unwrap_or_else(|_| "[]".to_string());
        let assignees_json = serde_json::to_string(&issue.assignees).unwrap_or_else(|_| "[]".to_string());

        sqlx::query(
            r#"
            INSERT INTO issues
                (id, external_id, provider, org_id, repo_name, number, title, body,
                 status, state_reason, labels, label_colors, assignees, author, url,
                 linked_pr_numbers, created_at, updated_at, synced_at, sync_with_provider)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', ?, ?, ?, 1)
            ON CONFLICT(id) DO UPDATE SET
                title        = excluded.title,
                body         = excluded.body,
                status       = excluded.status,
                state_reason = excluded.state_reason,
                labels       = excluded.labels,
                label_colors = excluded.label_colors,
                assignees    = excluded.assignees,
                author       = excluded.author,
                url          = excluded.url,
                updated_at   = excluded.updated_at,
                synced_at    = excluded.synced_at,
                sync_with_provider = 1
            "#,
        )
        .bind(&id)
        .bind(&issue.external_id)
        .bind(&provider_kind)
        .bind(&org_id)
        .bind(&repo_name)
        .bind(issue.number as i64)
        .bind(&issue.title)
        .bind(&issue.body)
        .bind(&issue.status)
        .bind(&issue.state_reason)
        .bind(&labels_json)
        .bind(&label_colors_json)
        .bind(&assignees_json)
        .bind(&issue.author)
        .bind(&issue.url)
        .bind(&issue.created_at)
        .bind(&issue.updated_at)
        .bind(&now)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    super::list::list(state, org_id, repo_name, Some(scope), current_login).await
}

async fn resolve_upstream(state: &AppState, org_id: &str, owner: &str, repo_name: &str) -> (String, String) {
    let result = sqlx::query_as::<_, (bool, Option<String>, Option<String>)>(
        "SELECT is_fork, fork_owner, fork_repo FROM organization_repos WHERE organization_id = ? AND repo_name = ? LIMIT 1",
    )
    .bind(org_id)
    .bind(repo_name)
    .fetch_optional(&state.db_pool)
    .await;

    match result {
        Ok(Some((true, Some(fo), Some(fr)))) => return (fo, fr),
        Ok(Some((true, _, _))) => {
            if let Some((fo, fr)) = crate::app::orgs::resolve_provider::fetch_and_persist_github_parent(state, org_id, owner, repo_name).await {
                return (fo, fr);
            }
        }
        _ => {}
    }

    (owner.to_string(), repo_name.to_string())
}
