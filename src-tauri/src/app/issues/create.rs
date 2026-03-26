use tauri::State;

use crate::app::issues::request::CreateIssueRequest;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn create(state: State<'_, AppState>, input: CreateIssueRequest) -> Result<IssueDto, String> {
    let (provider, owner) = super::resolve_provider::resolve_provider_and_owner(&state, &input.org_id, &input.repo_name).await?;
    let provider_kind = provider.kind().to_string();

    let issue = provider
        .create_issue(
            &owner,
            &input.repo_name,
            &input.title,
            input.body.as_deref(),
            input.labels.clone(),
            input.assignees.clone(),
        )
        .await
        .map_err(|e| e.to_string())?;

    let now = chrono::Utc::now().to_rfc3339();
    let id = format!("{}:{}:{}:{}", input.org_id, provider_kind, input.repo_name, issue.number);
    let labels_json = serde_json::to_string(&issue.labels).unwrap_or_else(|_| "[]".to_string());
    let label_colors_json = serde_json::to_string(&issue.label_colors).unwrap_or_else(|_| "[]".to_string());
    let assignees_json = serde_json::to_string(&issue.assignees).unwrap_or_else(|_| "[]".to_string());

    sqlx::query(
        r#"
        INSERT INTO issues
            (id, external_id, provider, org_id, repo_name, number, title, body,
             status, state_reason, labels, label_colors, assignees, author, url,
             linked_pr_numbers, created_at, updated_at, synced_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', ?, ?, ?)
        "#,
    )
    .bind(&id)
    .bind(&issue.external_id)
    .bind(&provider_kind)
    .bind(&input.org_id)
    .bind(&input.repo_name)
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

    super::get::get(state, input.org_id, input.repo_name, issue.number as i64)
        .await?
        .ok_or_else(|| "Issue was created but not found in DB".to_string())
}
