use tauri::State;

use crate::providers::types::IssueDto;
use crate::state::AppState;

pub async fn sync(state: State<'_, AppState>, org_id: String, owner: String, repo_name: String, state_filter: Option<String>) -> Result<Vec<IssueDto>, String> {
    let provider = super::resolve_provider::get_provider(&state, &org_id).await?;
    let provider_kind = provider.kind().to_string();
    let state_param = state_filter.as_deref();

    let issues = provider
        .list_issues(&owner, &repo_name, state_param)
        .await
        .map_err(|e| e.to_string())?;

    let now = chrono::Utc::now().to_rfc3339();

    for issue in &issues {
        let id = format!("{org_id}:{provider_kind}:{repo_name}:{}", issue.number);
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
                synced_at    = excluded.synced_at
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

    super::list::list(state, org_id, repo_name).await
}
