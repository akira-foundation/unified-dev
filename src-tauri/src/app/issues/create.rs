use tauri::State;

use crate::app::issues::request::CreateIssueRequest;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn create(state: State<'_, AppState>, input: CreateIssueRequest) -> Result<IssueDto, String> {
    let now = chrono::Utc::now().to_rfc3339();
    let (provider_kind, issue) = if input.sync_with_provider {
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

        (provider_kind, issue)
    } else {
        let next_number = sqlx::query_scalar::<_, Option<i64>>(
            "SELECT MAX(number) FROM issues WHERE org_id = ? AND repo_name = ?",
        )
        .bind(&input.org_id)
        .bind(&input.repo_name)
        .fetch_one(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?
        .unwrap_or(0)
            + 1;

        (
            "local".to_string(),
            crate::providers::dto::VcsIssue {
                external_id: format!("local:{}:{}:{}", input.org_id, input.repo_name, next_number),
                number: next_number as u64,
                title: input.title.clone(),
                body: input.body.clone(),
                status: "open".to_string(),
                state_reason: None,
                labels: input.labels.clone(),
                label_colors: vec!["888888".to_string(); input.labels.len()],
                assignees: input.assignees.clone(),
                author: None,
                url: String::new(),
                created_at: now.clone(),
                updated_at: now.clone(),
            },
        )
    };

    let id = format!("{}:{}:{}:{}", input.org_id, provider_kind, input.repo_name, issue.number);
    let labels_json = serde_json::to_string(&issue.labels).unwrap_or_else(|_| "[]".to_string());
    let label_colors_json = serde_json::to_string(&issue.label_colors).unwrap_or_else(|_| "[]".to_string());
    let assignees_json = serde_json::to_string(&issue.assignees).unwrap_or_else(|_| "[]".to_string());

    sqlx::query(
        r#"
        INSERT INTO issues
            (id, external_id, provider, org_id, repo_name, number, title, body,
             status, state_reason, labels, label_colors, assignees, author, url,
             linked_pr_numbers, created_at, updated_at, synced_at, sync_with_provider)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', ?, ?, ?, ?)
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
    .bind(input.sync_with_provider)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    super::get::get(state, input.org_id, input.repo_name, issue.number as i64)
        .await?
        .ok_or_else(|| "Issue was created but not found in DB".to_string())
}
