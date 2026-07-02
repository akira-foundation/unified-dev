use tauri::State;

use crate::app::settings::request::{scope_for_id, SyncSettingsDto, GLOBAL_ID};
use crate::app::support::error::AppResult;
use crate::database::records::SyncSettingsRecord;
use crate::state::AppState;

pub async fn get(id: String, state: State<'_, AppState>) -> AppResult<SyncSettingsDto> {
    let row = sqlx::query_as::<_, SyncSettingsRecord>("SELECT * FROM sync_settings WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.pool().await?)
        .await?;

    let dto = match row {
        Some(r) => SyncSettingsDto {
            id: r.id,
            scope: r.scope,
            sync_issues_enabled: r.sync_issues_enabled,
            sync_issues_interval_secs: r.sync_issues_interval_secs,
            sync_prs_enabled: r.sync_prs_enabled,
            sync_prs_interval_secs: r.sync_prs_interval_secs,
            sync_repos_enabled: r.sync_repos_enabled,
            sync_repos_interval_secs: r.sync_repos_interval_secs,
            sync_orgs_enabled: r.sync_orgs_enabled,
            sync_orgs_interval_secs: r.sync_orgs_interval_secs,
        },
        None => {
            if id == GLOBAL_ID {
                SyncSettingsDto::defaults_for(GLOBAL_ID)
            } else {
                let fallback_id = if scope_for_id(&id) == "repository" {
                    id.split(':').next().unwrap_or(GLOBAL_ID)
                } else {
                    GLOBAL_ID
                };

                let global = sqlx::query_as::<_, SyncSettingsRecord>(
                    "SELECT * FROM sync_settings WHERE id = ?",
                )
                .bind(fallback_id)
                .fetch_optional(&state.pool().await?)
                .await?;

                match global {
                    Some(g) => SyncSettingsDto {
                        id: id.clone(),
                        scope: scope_for_id(&id).to_string(),
                        sync_issues_enabled: g.sync_issues_enabled,
                        sync_issues_interval_secs: g.sync_issues_interval_secs,
                        sync_prs_enabled: g.sync_prs_enabled,
                        sync_prs_interval_secs: g.sync_prs_interval_secs,
                        sync_repos_enabled: g.sync_repos_enabled,
                        sync_repos_interval_secs: g.sync_repos_interval_secs,
                        sync_orgs_enabled: g.sync_orgs_enabled,
                        sync_orgs_interval_secs: g.sync_orgs_interval_secs,
                    },
                    None => SyncSettingsDto::defaults_for(&id),
                }
            }
        }
    };

    Ok(dto)
}
