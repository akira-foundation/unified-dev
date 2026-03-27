use tauri::State;

use crate::state::AppState;

pub async fn delete(
    state: State<'_, AppState>,
    org_id: String,
    repo_name: String,
    number: i64,
    issue_id: Option<String>,
) -> Result<(), String> {
    let row = if let Some(issue_id) = issue_id.clone() {
        sqlx::query_as::<_, (bool, String, String, i64)>(
            "SELECT sync_with_provider, org_id, repo_name, number FROM issues WHERE id = ? LIMIT 1",
        )
        .bind(&issue_id)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?
    } else {
        sqlx::query_as::<_, (bool, String, String, i64)>(
            "SELECT sync_with_provider, org_id, repo_name, number FROM issues WHERE org_id = ? AND repo_name = ? AND number = ? LIMIT 1",
        )
        .bind(&org_id)
        .bind(&repo_name)
        .bind(number)
        .fetch_optional(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?
    };

    let (sync_with_provider, resolved_org_id, resolved_repo_name, resolved_number) =
        row.ok_or_else(|| "Issue not found".to_string())?;

    if sync_with_provider {
        let (provider, owner) = super::resolve_provider::resolve_provider_and_owner(&state, &resolved_org_id, &resolved_repo_name).await?;

        let delete_result = provider
            .delete_issue(&owner, &resolved_repo_name, resolved_number as u64)
            .await;

        if let Err(error) = delete_result {
            let message = error.to_string();
            let already_deleted = message.contains("410 Gone")
                || message.contains("status\":\"410\"")
                || message.contains("This issue was deleted");

            if !already_deleted {
                return Err(message);
            }
        }
    }

    if let Some(issue_id) = issue_id {
        sqlx::query("DELETE FROM issues WHERE id = ?")
            .bind(&issue_id)
            .execute(&state.db_pool)
            .await
            .map_err(|e| e.to_string())?;
    } else {
        sqlx::query("DELETE FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?")
            .bind(&resolved_org_id)
            .bind(&resolved_repo_name)
            .bind(resolved_number)
            .execute(&state.db_pool)
            .await
            .map_err(|e| e.to_string())?;
    }

    Ok(())
}
