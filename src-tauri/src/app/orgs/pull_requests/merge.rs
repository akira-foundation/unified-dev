use tauri::State;

use crate::providers::enums::PrMergeStrategy;
use crate::state::AppState;

pub async fn merge(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
    strategy: PrMergeStrategy,
) -> Result<(), String> {
    let (owner, effective_repo, provider, _) =
        super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;

    provider
        .merge_pull_request(&owner, &effective_repo, pr_number, strategy)
        .await
        .map_err(|e| e.to_string())?;

    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE pull_requests
            SET state = 'closed',
                merged_at = ?,
                updated_at = ?,
                synced_at = ?
         WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(&now)
    .bind(&now)
    .bind(&now)
    .bind(&organization_id)
    .bind(&repo_name)
    .bind(pr_number as i64)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}
