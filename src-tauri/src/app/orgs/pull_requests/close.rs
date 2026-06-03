use tauri::State;

use crate::state::AppState;

pub async fn close(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
    comment: Option<String>,
) -> Result<(), String> {
    let (owner, effective_repo, provider, _) =
        super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;

    provider
        .close_pull_request(&owner, &effective_repo, pr_number, comment.as_deref())
        .await
        .map_err(|e| e.to_string())?;

    set_state(&state, &organization_id, &repo_name, pr_number, "closed").await
}

pub async fn reopen(
    state: State<'_, AppState>,
    organization_id: String,
    repo_name: String,
    pr_number: u64,
) -> Result<(), String> {
    let (owner, effective_repo, provider, _) =
        super::resolve_provider::resolve_pr_provider(&state, &organization_id, &repo_name).await?;

    provider
        .reopen_pull_request(&owner, &effective_repo, pr_number)
        .await
        .map_err(|e| e.to_string())?;

    set_state(&state, &organization_id, &repo_name, pr_number, "open").await
}

async fn set_state(
    state: &State<'_, AppState>,
    organization_id: &str,
    repo_name: &str,
    pr_number: u64,
    pr_state: &str,
) -> Result<(), String> {
    let now = chrono::Utc::now().to_rfc3339();
    sqlx::query(
        "UPDATE pull_requests
            SET state = ?,
                updated_at = ?,
                synced_at = ?
         WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(pr_state)
    .bind(&now)
    .bind(&now)
    .bind(organization_id)
    .bind(repo_name)
    .bind(pr_number as i64)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    let open_prs_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM pull_requests WHERE org_id = ? AND repo_name = ? AND state = 'open'",
    )
    .bind(organization_id)
    .bind(repo_name)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    sqlx::query(
        "UPDATE organization_repos SET open_prs_count = ? WHERE organization_id = ? AND repo_name = ?",
    )
    .bind(open_prs_count)
    .bind(organization_id)
    .bind(repo_name)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(())
}
