use tauri::State;

use crate::database::models::IssueRecord;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn get(state: State<'_, AppState>, org_id: String, repo_name: String, number: i64) -> Result<Option<IssueDto>, String> {
    let record = sqlx::query_as::<_, IssueRecord>(
        "SELECT * FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .bind(number)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(record.map(super::to_dto::record_to_dto))
}
