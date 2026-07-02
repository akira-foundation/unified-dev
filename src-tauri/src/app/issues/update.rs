use tauri::State;

use crate::app::issues::request::UpdateIssueRequest;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn update(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    issue_id: Option<String>,
    input: UpdateIssueRequest,
) -> Result<IssueDto, String> {
    let row = if let Some(issue_id) = issue_id.clone() {
        sqlx::query_as::<_, (bool, String, String, i64)>(
            "SELECT sync_with_provider, org_id, repo_name, number FROM issues WHERE id = ? LIMIT 1",
        )
        .bind(&issue_id)
        .fetch_optional(&state.pool().await.map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())?
    } else {
        sqlx::query_as::<_, (bool, String, String, i64)>(
            "SELECT sync_with_provider, org_id, repo_name, number FROM issues WHERE org_id = ? AND repo_name = ? AND number = ? LIMIT 1",
        )
        .bind(&org_id)
        .bind(&repo_name)
        .bind(number)
        .fetch_optional(&state.pool().await.map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())?
    };

    let (sync_with_provider, resolved_org_id, resolved_repo_name, resolved_number) =
        row.ok_or_else(|| "Issue not found".to_string())?;

    if sync_with_provider {
        let (provider, owner) = super::resolve_provider::resolve_provider_and_owner(
            &state,
            &resolved_org_id,
            &resolved_repo_name,
        )
        .await?;

        let issue = provider
            .update_issue(
                &owner,
                &resolved_repo_name,
                resolved_number as u64,
                input.title.as_deref(),
                input.body.as_deref(),
                input.status.as_deref(),
                input.labels.clone(),
                input.assignees.clone(),
            )
            .await
            .map_err(|e| e.to_string())?;

        let labels_json = serde_json::to_string(&issue.labels).unwrap_or_else(|_| "[]".to_string());
        let label_colors_json =
            serde_json::to_string(&issue.label_colors).unwrap_or_else(|_| "[]".to_string());
        let assignees_json =
            serde_json::to_string(&issue.assignees).unwrap_or_else(|_| "[]".to_string());
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            r#"
            UPDATE issues
            SET title = ?, body = ?, status = ?, state_reason = ?,
                labels = ?, label_colors = ?, assignees = ?, updated_at = ?, synced_at = ?
            WHERE org_id = ? AND repo_name = ? AND number = ?
            "#,
        )
        .bind(&issue.title)
        .bind(&issue.body)
        .bind(&issue.status)
        .bind(&issue.state_reason)
        .bind(&labels_json)
        .bind(&label_colors_json)
        .bind(&assignees_json)
        .bind(&issue.updated_at)
        .bind(&now)
        .bind(&resolved_org_id)
        .bind(&resolved_repo_name)
        .bind(resolved_number)
        .execute(&state.pool().await.map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())?;
    } else {
        let current = if let Some(issue_id) = issue_id.clone() {
            super::get::get_by_id(state.clone(), issue_id).await?
        } else {
            super::get::get(
                state.clone(),
                resolved_org_id.clone(),
                resolved_repo_name.clone(),
                resolved_number,
            )
            .await?
        }
        .ok_or_else(|| "Issue not found".to_string())?;

        let next_title = input.title.unwrap_or(current.title);
        let next_body = input.body.or(current.body);
        let next_status = input.status.unwrap_or(current.status);
        let next_labels = input.labels.unwrap_or(current.labels);
        let next_assignees = input.assignees.unwrap_or(current.assignees);
        let labels_json = serde_json::to_string(&next_labels).unwrap_or_else(|_| "[]".to_string());
        let assignees_json =
            serde_json::to_string(&next_assignees).unwrap_or_else(|_| "[]".to_string());
        let now = chrono::Utc::now().to_rfc3339();

        sqlx::query(
            r#"
            UPDATE issues
            SET title = ?, body = ?, status = ?, labels = ?, assignees = ?, updated_at = ?
            WHERE org_id = ? AND repo_name = ? AND number = ?
            "#,
        )
        .bind(&next_title)
        .bind(&next_body)
        .bind(&next_status)
        .bind(&labels_json)
        .bind(&assignees_json)
        .bind(&now)
        .bind(&resolved_org_id)
        .bind(&resolved_repo_name)
        .bind(resolved_number)
        .execute(&state.pool().await.map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())?;
    }

    if let Some(issue_id) = issue_id {
        super::get::get_by_id(state, issue_id)
            .await?
            .ok_or_else(|| "Issue not found after update".to_string())
    } else {
        super::get::get(state, resolved_org_id, resolved_repo_name, resolved_number)
            .await?
            .ok_or_else(|| "Issue not found after update".to_string())
    }
}
