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

    let open_prs_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM pull_requests WHERE org_id = ? AND repo_name = ? AND state = 'open'",
    )
    .bind(&organization_id)
    .bind(&repo_name)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    sqlx::query(
        "UPDATE organization_repos SET open_prs_count = ? WHERE organization_id = ? AND repo_name = ?",
    )
    .bind(open_prs_count)
    .bind(&organization_id)
    .bind(&repo_name)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    close_linked_issues(&state, &organization_id, &repo_name, pr_number).await;

    Ok(())
}

async fn close_linked_issues(
    state: &State<'_, AppState>,
    organization_id: &str,
    repo_name: &str,
    pr_number: u64,
) {
    let body: Option<String> = sqlx::query_scalar::<_, Option<String>>(
        "SELECT body FROM pull_requests WHERE org_id = ? AND repo_name = ? AND number = ?",
    )
    .bind(organization_id)
    .bind(repo_name)
    .bind(pr_number as i64)
    .fetch_optional(&state.db_pool)
    .await
    .ok()
    .flatten()
    .flatten();

    for number in super::linked_issues::parse_closing_issue_numbers(body.as_deref()) {
        if let Err(e) = crate::app::issues::close(
            state.clone(),
            organization_id.to_string(),
            repo_name.to_string(),
            number as i64,
            Some("completed".to_string()),
        )
        .await
        {
            eprintln!("failed to close issue #{number} linked to PR #{pr_number}: {e}");
        }
    }
}
