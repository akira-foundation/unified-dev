use tauri::{AppHandle, Emitter, State};

use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn touch(org_id: String, state: State<'_, AppState>, app: AppHandle) -> AppResult<()> {
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO sync_settings (
            id, scope,
            sync_issues_enabled, sync_issues_interval_secs,
            sync_prs_enabled, sync_prs_interval_secs,
            sync_repos_enabled, sync_repos_interval_secs,
            sync_orgs_enabled, sync_orgs_interval_secs,
            created_at, updated_at
        )
        VALUES (?, 'organization', 1, 900, 1, 300, 1, 1800, 1, 7200, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at",
    )
    .bind(&org_id)
    .bind(&now)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;

    let _ = app.emit(
        "sync:completed",
        serde_json::json!({ "kind": "manual", "orgId": org_id }),
    );

    Ok(())
}
