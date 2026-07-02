use tauri::State;

use crate::app::settings::request::{scope_for_id, SyncSettingsDto, UpsertSyncSettingsRequest};
use crate::app::support::error::AppResult;
use crate::state::AppState;

pub async fn upsert(
    input: UpsertSyncSettingsRequest,
    state: State<'_, AppState>,
) -> AppResult<SyncSettingsDto> {
    let scope = scope_for_id(&input.id);
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        r#"
        INSERT INTO sync_settings (
            id, scope,
            sync_issues_enabled, sync_issues_interval_secs,
            sync_prs_enabled, sync_prs_interval_secs,
            sync_repos_enabled, sync_repos_interval_secs,
            sync_orgs_enabled, sync_orgs_interval_secs,
            created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            scope                     = excluded.scope,
            sync_issues_enabled       = excluded.sync_issues_enabled,
            sync_issues_interval_secs = excluded.sync_issues_interval_secs,
            sync_prs_enabled          = excluded.sync_prs_enabled,
            sync_prs_interval_secs    = excluded.sync_prs_interval_secs,
            sync_repos_enabled        = excluded.sync_repos_enabled,
            sync_repos_interval_secs  = excluded.sync_repos_interval_secs,
            sync_orgs_enabled         = excluded.sync_orgs_enabled,
            sync_orgs_interval_secs   = excluded.sync_orgs_interval_secs,
            updated_at                = excluded.updated_at
        "#,
    )
    .bind(&input.id)
    .bind(scope)
    .bind(input.sync_issues_enabled)
    .bind(input.sync_issues_interval_secs)
    .bind(input.sync_prs_enabled)
    .bind(input.sync_prs_interval_secs)
    .bind(input.sync_repos_enabled)
    .bind(input.sync_repos_interval_secs)
    .bind(input.sync_orgs_enabled)
    .bind(input.sync_orgs_interval_secs)
    .bind(&now)
    .bind(&now)
    .execute(&state.pool().await?)
    .await?;

    Ok(SyncSettingsDto {
        id: input.id,
        scope: scope.to_string(),
        sync_issues_enabled: input.sync_issues_enabled,
        sync_issues_interval_secs: input.sync_issues_interval_secs,
        sync_prs_enabled: input.sync_prs_enabled,
        sync_prs_interval_secs: input.sync_prs_interval_secs,
        sync_repos_enabled: input.sync_repos_enabled,
        sync_repos_interval_secs: input.sync_repos_interval_secs,
        sync_orgs_enabled: input.sync_orgs_enabled,
        sync_orgs_interval_secs: input.sync_orgs_interval_secs,
    })
}
