use tauri::State;

use crate::state::AppState;

pub async fn delete_issue(state: State<'_, AppState>, org_id: String, repo_name: String, number: i64) -> Result<(), String> {
    let (provider, owner) = super::resolve_provider::resolve_provider_and_owner(&state, &org_id, &repo_name).await?;

    provider
        .delete_issue(&owner, &repo_name, number as u64)
        .await
        .map_err(|e| e.to_string())?;

    sqlx::query("DELETE FROM issues WHERE org_id = ? AND repo_name = ? AND number = ?")
        .bind(&org_id)
        .bind(&repo_name)
        .bind(number)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

    Ok(())
}
