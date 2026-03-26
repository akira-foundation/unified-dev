use tauri::State;

use crate::state::AppState;

pub async fn delete(state: State<'_, AppState>, org_id: String, repo_name: String, number: i64) -> Result<(), String> {
    let sync_with_provider = sqlx::query_scalar::<_, Option<bool>>(
        "SELECT sync_with_provider FROM issues WHERE org_id = ? AND repo_name = ? AND number = ? LIMIT 1",
    )
    .bind(&org_id)
    .bind(&repo_name)
    .bind(number)
    .fetch_optional(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?
    .flatten()
    .unwrap_or(true);

    if sync_with_provider {
        let (provider, owner) = super::resolve_provider::resolve_provider_and_owner(&state, &org_id, &repo_name).await?;

        let delete_result = provider
            .delete_issue(&owner, &repo_name, number as u64)
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

    sqlx::query("DELETE FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?")
        .bind(&org_id)
        .bind(&repo_name)
        .bind(number)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}
