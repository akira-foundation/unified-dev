use tauri::State;

use crate::database::records::IssueRecord;
use crate::providers::dto::IssueDto;
use crate::state::AppState;

pub async fn list(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    scope: Option<String>,
    current_login: Option<String>,
) -> Result<Vec<IssueDto>, String> {
    let records = sqlx::query_as::<_, IssueRecord>(
        "SELECT * FROM issues WHERE org_id = ? AND repo_name = ? ORDER BY number DESC",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .fetch_all(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let scope = scope.unwrap_or_else(|| "my_queue".to_string());
    let login = current_login.map(|value| value.to_lowercase());

    Ok(records
        .into_iter()
        .map(super::to_dto::record_to_dto)
        .filter(|issue| match scope.as_str() {
            "all" => true,
            "all_open" => issue.status == "open",
            _ => {
                if issue.status != "open" {
                    return false;
                }

                if !issue.sync_with_provider {
                    return true;
                }

                if issue.assignees.is_empty() {
                    return true;
                }

                login.as_ref().map(|current| {
                    issue.assignees.iter().any(|assignee| assignee.to_lowercase() == *current)
                }).unwrap_or(false)
            }
        })
        .collect())
}
