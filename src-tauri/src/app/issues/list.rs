use tauri::State;

use crate::database::records::IssueRecord;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn list(state: State<'_, AppState>, org_id: String, repo_name: String) -> Result<Vec<IssueDto>, String> {
    let records = sqlx::query_as::<_, IssueRecord>(
        "SELECT * FROM issues WHERE org_id = ? AND repo_name = ? ORDER BY number DESC",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(records.into_iter().map(super::to_dto::record_to_dto).collect())
}
