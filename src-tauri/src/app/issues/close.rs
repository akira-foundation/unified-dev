use tauri::State;

use crate::state::AppState;

pub async fn close(state: State<'_, AppState>, org_id: String, repo_name: String, number: i64, reason: Option<String>) -> Result<(), String> {
    let (provider, owner) = super::resolve_provider::resolve_provider_and_owner(&state, &org_id, &repo_name).await?;

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
