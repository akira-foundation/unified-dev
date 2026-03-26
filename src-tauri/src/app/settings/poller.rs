use std::collections::HashMap;
use std::time::{Duration, Instant};

use tauri::{AppHandle, Emitter, Manager};

use crate::app::settings::request::{SyncSettingsDto, GLOBAL_ID};
use crate::state::AppState;

const TICK_SECS: u64 = 30;

pub fn start(app_handle: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let mut last_synced: HashMap<(&'static str, String), Instant> = HashMap::new();

        loop {
            tokio::time::sleep(Duration::from_secs(TICK_SECS)).await;

            let state = app_handle.state::<AppState>();
            let now = Instant::now();
            let global = load_settings(&state, GLOBAL_ID).await;

            let orgs: Vec<(String,)> = match sqlx::query_as(
                "SELECT id FROM organizations ORDER BY name",
            )
            .fetch_all(&state.db_pool)
            .await
            {
                Ok(rows) => rows,
                Err(_) => continue,
            };

            let repos: Vec<(String, String, String)> = match sqlx::query_as(
                "SELECT organization_id, owner, repo_name FROM organization_repos WHERE is_selected = 1",
            )
            .fetch_all(&state.db_pool)
            .await
            {
                Ok(rows) => rows,
                Err(_) => continue,
            };

            for (org_id,) in &orgs {
                let has_override = sqlx::query_scalar::<_, i64>(
                    "SELECT COUNT(*) FROM sync_settings WHERE id = ?",
                )
                .bind(org_id)
                .fetch_one(&state.db_pool)
                .await
                .unwrap_or(0)
                    > 0;

                let settings = if has_override {
                    load_settings(&state, org_id).await
                } else {
                    global.clone()
                };

                let org_repos: Vec<(&String, &String)> = repos
                    .iter()
                    .filter(|(oid, _, _)| oid == org_id)
                    .map(|(_, owner, repo)| (owner, repo))
                    .collect();

                if settings.sync_repos_enabled
                    && due(&last_synced, "repos", org_id, settings.sync_repos_interval_secs, now)
                {
                    let _ = crate::app::orgs::repos::sync_stats::sync_stats(
                        app_handle.state::<AppState>(),
                        org_id.clone(),
                    )
                    .await;
                    last_synced.insert(("repos", org_id.clone()), now);
                    touch_synced_at(&state, org_id, &settings).await;
                    emit(&app_handle, "repos", org_id);
                }

                if settings.sync_prs_enabled
                    && due(&last_synced, "prs", org_id, settings.sync_prs_interval_secs, now)
                {
                    for (owner, repo) in &org_repos {
                        let _ = crate::app::orgs::pull_requests::sync::sync(
                            app_handle.state::<AppState>(),
                            org_id.clone(),
                            repo.to_string(),
                            Some(owner.to_string()),
                        )
                        .await;
                    }
                    last_synced.insert(("prs", org_id.clone()), now);
                    touch_synced_at(&state, org_id, &settings).await;
                    emit(&app_handle, "prs", org_id);
                }

                if settings.sync_issues_enabled
                    && due(&last_synced, "issues", org_id, settings.sync_issues_interval_secs, now)
                {
                    for (owner, repo) in &org_repos {
                        let _ = crate::app::issues::sync::sync(
                            app_handle.state::<AppState>(),
                            org_id.clone(),
                            owner.to_string(),
                            repo.to_string(),
                            None,
                        )
                        .await;
                    }
                    last_synced.insert(("issues", org_id.clone()), now);
                    touch_synced_at(&state, org_id, &settings).await;
                    emit(&app_handle, "issues", org_id);
                }
            }

            if global.sync_orgs_enabled
                && due(&last_synced, "orgs", GLOBAL_ID, global.sync_orgs_interval_secs, now)
            {
                let provider_ids: Vec<String> =
                    sqlx::query_scalar::<_, String>("SELECT id FROM providers")
                        .fetch_all(&state.db_pool)
                        .await
                        .unwrap_or_default();

                for provider_id in provider_ids {
                    let _ = sync_orgs(app_handle.state::<AppState>(), &provider_id).await;
                }

                last_synced.insert(("orgs", GLOBAL_ID.to_string()), now);
                emit(&app_handle, "orgs", GLOBAL_ID);
            }
        }
    });
}

fn due(
    last: &HashMap<(&'static str, String), Instant>,
    kind: &'static str,
    id: &str,
    interval_secs: i64,
    now: Instant,
) -> bool {
    match last.get(&(kind, id.to_string())) {
        None => true,
        Some(t) => now.duration_since(*t) >= Duration::from_secs(interval_secs as u64),
    }
}

fn emit(app_handle: &AppHandle, kind: &str, org_id: &str) {
    let _ = app_handle.emit(
        "sync:completed",
        serde_json::json!({ "kind": kind, "orgId": org_id }),
    );
}

async fn load_settings(state: &AppState, id: &str) -> SyncSettingsDto {
    sqlx::query_as::<_, crate::database::records::SyncSettingsRecord>(
        "SELECT * FROM sync_settings WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(&state.db_pool)
    .await
    .ok()
    .flatten()
    .map(|r| SyncSettingsDto {
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
    })
    .unwrap_or_else(|| SyncSettingsDto::defaults_for(id))
}

async fn touch_synced_at(state: &AppState, id: &str, settings: &SyncSettingsDto) {
    let scope = if id == GLOBAL_ID { "global" } else { "organization" };
    let now = chrono::Utc::now().to_rfc3339();
    let _ = sqlx::query(
        "INSERT INTO sync_settings (
            id, scope,
            sync_issues_enabled, sync_issues_interval_secs,
            sync_prs_enabled, sync_prs_interval_secs,
            sync_repos_enabled, sync_repos_interval_secs,
            sync_orgs_enabled, sync_orgs_interval_secs,
            created_at, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET updated_at = excluded.updated_at",
    )
    .bind(id)
    .bind(scope)
    .bind(settings.sync_issues_enabled)
    .bind(settings.sync_issues_interval_secs)
    .bind(settings.sync_prs_enabled)
    .bind(settings.sync_prs_interval_secs)
    .bind(settings.sync_repos_enabled)
    .bind(settings.sync_repos_interval_secs)
    .bind(settings.sync_orgs_enabled)
    .bind(settings.sync_orgs_interval_secs)
    .bind(&now)
    .bind(&now)
    .execute(&state.db_pool)
    .await;
}

async fn sync_orgs(state: tauri::State<'_, AppState>, provider_id: &str) -> Result<(), String> {
    let credentials = crate::app::providers::credentials::credentials(&state, provider_id)
        .await
        .map_err(|e| e.to_string())?;

    let provider = state
        .provider_factory
        .create(&credentials.kind, credentials.auth)
        .await
        .map_err(|e| e.to_string())?;

    let remote_orgs = provider
        .list_organizations()
        .await
        .map_err(|e| e.to_string())?;

    let now = chrono::Utc::now().to_rfc3339();

    for org in remote_orgs {
        sqlx::query(
            "INSERT INTO organizations (id, name, provider_id, external_id, created_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(provider_id, external_id) DO UPDATE SET name = excluded.name",
        )
        .bind(uuid::Uuid::new_v4().to_string())
        .bind(&org.login)
        .bind(provider_id)
        .bind(&org.id)
        .bind(&now)
        .execute(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;
    }

    Ok(())
}
