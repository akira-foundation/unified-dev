use tauri::State;

use crate::app::issues::request::UpdateIssueRequest;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn update(state: State<'_, AppState>, org_id: String, repo_name: String, number: i64, input: UpdateIssueRequest) -> Result<IssueDto, String> {
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

    super::get::get(state, org_id, repo_name, number)
        .await?
        .ok_or_else(|| "Issue not found after update".to_string())
}
