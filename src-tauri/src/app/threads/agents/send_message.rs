use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use akira_billing::types::UsagePayload;
use tauri::{AppHandle, State};

use crate::app::billing::PRODUCT_SLUG;
use crate::app::chat::session;
use crate::app::chat::stream::emit_error;
use crate::app::support::error::AppResult;
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
    track_usage_fire_and_forget(&state).await;

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

async fn track_usage_fire_and_forget(state: &State<'_, AppState>) {
    let Ok(pool) = state.pool().await else {
        return;
    };
    let date = chrono::Utc::now().format("%Y-%m-%d").to_string();
    let fingerprint = crate::app::license::device_fingerprint();
    let has_token = crate::app::license::load_customer_token(&pool, &state.token_cipher)
        .await
        .ok()
        .flatten()
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
    let _ = if has_token {
        billing.inner().track_usage(payload).await
    } else {
        billing.inner().track_anonymous_usage(payload).await
    };
}
