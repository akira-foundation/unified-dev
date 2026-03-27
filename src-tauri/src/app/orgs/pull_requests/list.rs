use tauri::State;

use crate::database::records::PullRequestRecord;
use crate::providers::dto::PullRequestDto;
use crate::state::AppState;

pub async fn list(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<PullRequestDto>, String> {
    let records = sqlx::query_as::<_, PullRequestRecord>(
        "SELECT * FROM pull_requests WHERE org_id = ? AND repo_name = ? AND state = 'open' ORDER BY number DESC",
    )
    .bind(&organization_id)
    .bind(&repo_name)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    if records.is_empty() {
        return super::sync::sync(state, organization_id, repo_name, None, scope, current_login).await;
    }

    let scope = scope.unwrap_or_else(|| "mine_or_review_requested".to_string());
    let login = current_login.map(|v| v.to_lowercase());

    Ok(records
        .into_iter()
        .map(record_to_dto)
        .filter(|pr| match scope.as_str() {
            "all_open" => true,
            _ => login.as_ref().map(|current| {
                pr.author.as_ref().map(|a| a.to_lowercase() == *current).unwrap_or(false)
                    || pr.reviewers.iter().any(|r| r.to_lowercase() == *current)
            }).unwrap_or(true),
        })
        .collect())
}

fn record_to_dto(r: PullRequestRecord) -> PullRequestDto {
    PullRequestDto {
        id: r.external_id,
        number: r.number as u64,
        title: r.title,
        state: r.state,
        url: r.url,
        head: r.head,
        base: r.base,
        head_sha: r.head_sha,
        created_at: r.created_at,
        updated_at: r.updated_at,
        is_draft: r.is_draft,
        merged_at: r.merged_at,
        body: r.body,
        author: r.author,
        labels: serde_json::from_str(&r.labels).unwrap_or_default(),
        reviewers: serde_json::from_str(&r.reviewers).unwrap_or_default(),
        ci_status: r.ci_status,
    }
}
