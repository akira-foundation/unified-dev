use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use akira_billing::types::UsagePayload;
use tauri::{AppHandle, State};

use crate::app::billing::PRODUCT_SLUG;
use crate::app::chat::session;
use crate::app::chat::stream::emit_error;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;
use tokio::task::JoinHandle;

const USAGE_FEATURE: &str = "agent_run";

pub async fn spawn_send_message(
    thread_id: String,
    message: String,
    model: String,
    silent: Option<bool>,
    plan_mode: Option<bool>,
    thinking_budget: Option<String>,
    fast_mode: Option<bool>,
    pool: sqlx::SqlitePool,
    abort_handles: Arc<Mutex<HashMap<String, JoinHandle<()>>>>,
    app: AppHandle,
) -> AppResult<()> {
    let app = app.clone();
    let thread_id_err = thread_id.clone();
    let thread_id_map = thread_id.clone();
    let silent = silent.unwrap_or(false);
    let plan_mode = plan_mode.unwrap_or(false);
    let thinking_budget = thinking_budget.unwrap_or_else(|| "medium".to_string());
    let fast_mode = fast_mode.unwrap_or(false);

    let handle = tokio::spawn(async move {
        if let Err(e) = session::run(
            thread_id,
            message,
            model,
            silent,
            plan_mode,
            thinking_budget,
            fast_mode,
            pool,
            app.clone(),
        )
        .await
        {
            emit_error(&app, &thread_id_err, &e.to_string());
        }
    });

    if let Ok(mut map) = abort_handles.lock() {
        map.insert(thread_id_map, handle);
    }

    Ok(())
}

pub async fn send_message(
    thread_id: String,
    message: String,
    model: String,
    silent: Option<bool>,
    plan_mode: Option<bool>,
    thinking_budget: Option<String>,
    fast_mode: Option<bool>,
    state: State<'_, AppState>,
    app: AppHandle,
) -> AppResult<()> {
    let lifecycle_state =
        crate::app::license::lifecycle::current_state(&state.pool().await?).await?;
    let plan = crate::app::license::get_plan(&state.pool().await?).await?;
    let effective_free = !matches!(
        lifecycle_state,
        akira_billing::lifecycle::LicenseState::Active
            | akira_billing::lifecycle::LicenseState::Trialing
    ) || plan == "free";
    if effective_free {
        let date = chrono::Utc::now().format("%Y-%m-%d").to_string();
        let fingerprint = crate::app::license::device_fingerprint();
        let has_token =
            crate::app::license::load_customer_token(&state.pool().await?, &state.token_cipher)
                .await?
                .is_some();
        let platform = std::env::consts::OS;
        let app_version = env!("CARGO_PKG_VERSION");
        let payload = UsagePayload {
            product: PRODUCT_SLUG,
            feature: USAGE_FEATURE,
            date: &date,
            device_fp: &fingerprint,
            action: "increment",
            count: None,
            platform: Some(platform),
            device_type: Some("desktop"),
            app_version: Some(app_version),
        };

        let billing = state.billing.read().await;
        let response = if has_token {
            billing
                .inner()
                .track_usage(payload)
                .await
                .map_err(|e| translate_billing_error(e, "track_usage"))?
        } else {
            billing
                .inner()
                .track_anonymous_usage(payload)
                .await
                .map_err(|e| translate_billing_error(e, "track_anonymous_usage"))?
        };

        if !response.allowed {
            let _ = crate::app::notifications::notify(
                &app,
                crate::app::notifications::NotificationInput {
                    category: crate::app::notifications::NotificationCategory::UsageLimit,
                    severity: crate::app::notifications::NotificationSeverity::Warning,
                    title: "Daily agent run limit reached".to_string(),
                    body: response.limit.map(|limit| {
                        format!(
                            "{}/{} runs used today. Upgrade to Pro for unlimited.",
                            response.count, limit
                        )
                    }),
                    action_type: Some("upgrade.pro".to_string()),
                    action_payload: None,
                    ttl_days: Some(1),
                },
            )
            .await;
            return Err(AppError::FreeTierLimit("run_limit_reached".to_string()));
        }

        if let Some(limit) = response.limit {
            if limit > 0 && response.count + 1 == limit {
                let _ = crate::app::notifications::notify(
                    &app,
                    crate::app::notifications::NotificationInput {
                        category: crate::app::notifications::NotificationCategory::UsageLimit,
                        severity: crate::app::notifications::NotificationSeverity::Info,
                        title: "Approaching daily run limit".to_string(),
                        body: Some(format!(
                            "Last run of the day. {}/{} used.",
                            response.count, limit
                        )),
                        action_type: Some("upgrade.pro".to_string()),
                        action_payload: None,
                        ttl_days: Some(1),
                    },
                )
                .await;
            }
        }
    }

    spawn_send_message(
        thread_id,
        message,
        model,
        silent,
        plan_mode,
        thinking_budget,
        fast_mode,
        state.pool().await?,
        state.abort_handles.clone(),
        app,
    )
    .await
}

fn translate_billing_error(err: akira_billing::Error, context: &str) -> AppError {
    use akira_billing::Error as BErr;
    match err {
        BErr::Api { status, code, .. } => {
            if !code.is_empty() {
                AppError::Internal(code)
            } else {
                AppError::Internal(format!("billing {context} failed: HTTP {status}"))
            }
        }
        other => AppError::Internal(format!("billing {context}: {other}")),
    }
}
