use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use tauri::{AppHandle, State};

use crate::app::chat::session;
use crate::app::chat::stream::emit_error;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;
use tokio::task::JoinHandle;

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");

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
            thread_id, message, model, silent,
            plan_mode, thinking_budget, fast_mode,
            pool, app.clone(),
        ).await {
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
    let plan = crate::app::license::get_plan(&state.db_pool).await?;
    if plan == "free" {
        let token = crate::app::license::get_token(&state.db_pool)
            .await?
            .unwrap_or_default();
        let date = chrono::Utc::now().format("%Y-%m-%d").to_string();

        let mut identity = crate::app::license::machine_id::get_or_create(&app)?;

        let client = reqwest::Client::new();
        let res = client
            .post(format!("{AKIRA_API_URL}/billing/usage"))
            .json(&serde_json::json!({
                "machine_id": identity.id,
                "token": token,
                "action": "increment",
                "date": date,
                "created_at_sig": identity.created_at_sig,
            }))
            .send()
            .await
            .map_err(AppError::Http)?;

        let body: serde_json::Value = res.json().await.map_err(AppError::Http)?;

        if let Some(sig) = body["created_at_sig"].as_str() {
            if identity.created_at_sig.as_deref() != Some(sig) {
                identity.created_at_sig = Some(sig.to_string());
                let _ = crate::app::license::machine_id::save(&app, &identity);
            }
        }

        if body["allowed"].as_bool() != Some(true) {
            return Err(AppError::FreeTierLimit("run_limit_reached".to_string()));
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
        state.db_pool.clone(),
        state.abort_handles.clone(),
        app,
    ).await
}
