use tauri::State;

use crate::app::issues::request::UpdateIssueRequest;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn update(state: State<'_, AppState>, org_id: String, repo_name: String, number: i64, input: UpdateIssueRequest) -> Result<IssueDto, String> {
    let sync_with_provider = sqlx::query_scalar::<_, Option<bool>>(
        "SELECT sync_with_provider FROM issues WHERE org_id = ? AND repo_name = ? AND number = ? LIMIT 1",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .bind(number)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?
    .flatten()
    .unwrap_or(true);

    if sync_with_provider {
        let (provider, owner) = super::resolve_provider::resolve_provider_and_owner(&state, &org_id, &repo_name).await?;

        let issue = provider
            .update_issue(
                &owner,
                &repo_name,
                number as u64,
                input.title.as_deref(),
                input.body.as_deref(),
                input.status.as_deref(),
                input.labels.clone(),
                input.assignees.clone(),
            )
            .await
            .map_err(|e| e.to_string())?;

        let labels_json = serde_json::to_string(&issue.labels).unwrap_or_else(|_| "[]".to_string());
        let label_colors_json = serde_json::to_string(&issue.label_colors).unwrap_or_else(|_| "[]".to_string());
        let assignees_json = serde_json::to_string(&issue.assignees).unwrap_or_else(|_| "[]".to_string());
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
        .bind(&org_id)
        .bind(&repo_name)
        .bind(number)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    } else {
        let current = super::get::get(state.clone(), org_id.clone(), repo_name.clone(), number)
            .await?
            .ok_or_else(|| "Issue not found".to_string())?;

        let next_title = input.title.unwrap_or(current.title);
        let next_body = input.body.or(current.body);
        let next_status = input.status.unwrap_or(current.status);
        let next_labels = input.labels.unwrap_or(current.labels);
        let next_assignees = input.assignees.unwrap_or(current.assignees);
        let labels_json = serde_json::to_string(&next_labels).unwrap_or_else(|_| "[]".to_string());
        let assignees_json = serde_json::to_string(&next_assignees).unwrap_or_else(|_| "[]".to_string());
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
        .bind(&org_id)
        .bind(&repo_name)
        .bind(number)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    super::get::get(state, org_id, repo_name, number)
        .await?
        .ok_or_else(|| "Issue not found after update".to_string())
}
