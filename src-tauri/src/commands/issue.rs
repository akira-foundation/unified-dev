use tauri::State;

use crate::providers::shared::types::IssueDto;
use crate::db::inputs::{CreateIssueInput, UpdateIssueInput};
use crate::db::models::IssueRecord;
use crate::state::AppState;

async fn get_provider(
    state: &AppState,
    org_id: &str,
) -> Result<std::sync::Arc<dyn crate::providers::shared::traits::VcsProvider>, String> {
    let provider_id = sqlx::query_scalar::<_, Option<String>>(
        "SELECT provider_id FROM organizations WHERE id = ?",
    )
    .bind(org_id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?
    .ok_or_else(|| "Organization has no provider".to_string())?;

    let credentials = state
        .provider_service
        .credentials(&provider_id)
        .await
        .map_err(|e| e.to_string())?;

    state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|e| e.to_string())
}

async fn resolve_owner(state: &AppState, org_id: &str, repo_name: &str) -> Result<String, String> {
    sqlx::query_scalar::<_, String>(
        "SELECT owner FROM organization_repos WHERE organization_id = ? AND repo_name = ? LIMIT 1",
    )
    .bind(org_id)
    .bind(repo_name)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}

async fn resolve_provider_and_owner(
    state: &AppState,
    org_id: &str,
    repo_name: &str,
) -> Result<(std::sync::Arc<dyn crate::providers::shared::traits::VcsProvider>, String), String> {
    let provider = get_provider(state, org_id).await?;
    let owner = resolve_owner(state, org_id, repo_name).await?;
    Ok((provider, owner))
}

fn record_to_dto(r: IssueRecord) -> IssueDto {
    let labels: Vec<String> = serde_json::from_str(&r.labels).unwrap_or_default();
    let label_colors: Vec<String> = serde_json::from_str(&r.label_colors).unwrap_or_default();
    let assignees: Vec<String> = serde_json::from_str(&r.assignees).unwrap_or_default();
    let linked_pr_numbers: Vec<u64> = serde_json::from_str(&r.linked_pr_numbers).unwrap_or_default();

    IssueDto {
        id: r.id,
        external_id: r.external_id,
        provider: r.provider,
        org_id: r.org_id,
        repo_name: r.repo_name,
        number: r.number,
        title: r.title,
        body: r.body,
        status: r.status,
        state_reason: r.state_reason,
        labels,
        label_colors,
        assignees,
        author: r.author,
        url: r.url,
        linked_pr_numbers,
        created_at: r.created_at,
        updated_at: r.updated_at,
        synced_at: r.synced_at,
    }
}

#[tauri::command]
pub async fn sync_issues(
    state: State<'_, AppState>,
    org_id: String,
    owner: String,
    repo_name: String,
    state_filter: Option<String>,
) -> Result<Vec<IssueDto>, String> {
    let provider = get_provider(&state, &org_id).await?;
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

    list_issues(state, org_id, repo_name).await
}

#[tauri::command]
pub async fn list_issues(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
) -> Result<Vec<IssueDto>, String> {
    let records = sqlx::query_as::<_, IssueRecord>(
        "SELECT * FROM issues WHERE org_id = ? AND repo_name = ? ORDER BY number DESC",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(records.into_iter().map(record_to_dto).collect())
}

#[tauri::command]
pub async fn get_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
) -> Result<Option<IssueDto>, String> {
    let record = sqlx::query_as::<_, IssueRecord>(
        "SELECT * FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .bind(number)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(record.map(record_to_dto))
}

#[tauri::command]
pub async fn create_issue(
    state: State<'_, AppState>,
    input: CreateIssueInput,
) -> Result<IssueDto, String> {
    let (provider, owner) = resolve_provider_and_owner(&state, &input.org_id, &input.repo_name).await?;
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

    get_issue(state, input.org_id, input.repo_name, issue.number as i64)
        .await?
        .ok_or_else(|| "Issue was created but not found in DB".to_string())
}

#[tauri::command]
pub async fn update_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    input: UpdateIssueInput,
) -> Result<IssueDto, String> {
    let (provider, owner) = resolve_provider_and_owner(&state, &org_id, &repo_name).await?;

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

    get_issue(state, org_id, repo_name, number)
        .await?
        .ok_or_else(|| "Issue not found after update".to_string())
}

#[tauri::command]
pub async fn delete_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
) -> Result<(), String> {
    let (provider, owner) = resolve_provider_and_owner(&state, &org_id, &repo_name).await?;

    provider
        .delete_issue(&owner, &repo_name, number as u64)
        .await
        .map_err(|e| e.to_string())?;

    sqlx::query(
        "DELETE FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .bind(number)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}

#[tauri::command]
pub async fn close_issue(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    reason: Option<String>,
) -> Result<(), String> {
    let (provider, owner) = resolve_provider_and_owner(&state, &org_id, &repo_name).await?;

    provider
        .close_issue(&owner, &repo_name, number as u64, reason.as_deref())
        .await
        .map_err(|e| e.to_string())?;

    let now = chrono::Utc::now().to_rfc3339();
    let state_reason = reason.unwrap_or_else(|| "completed".to_string());

    sqlx::query(
        "UPDATE issues SET status = 'closed', state_reason = ?, synced_at = ? WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(&state_reason)
    .bind(&now)
    .bind(&org_id)
    .bind(&repo_name)
    .bind(number)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}
