use tauri::State;

use crate::database::records::IssueRecord;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn get_by_id(
    state: State<'_, AppState>,
    issue_id: String,
) -> Result<Option<IssueDto>, String> {
    let record = sqlx::query_as::<_, IssueRecord>("SELECT * FROM issues WHERE id = ? LIMIT 1")
        .bind(&issue_id)
        .fetch_optional(&state.pool().await.map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())?;

    Ok(record.map(super::to_dto::record_to_dto))
}

pub async fn get(
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
    .fetch_optional(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())?;

    Ok(record.map(super::to_dto::record_to_dto))
}
