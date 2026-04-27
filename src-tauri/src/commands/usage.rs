use serde::Serialize;
use tauri::{AppHandle, State};

use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");
const FREE_RUN_LIMIT: u32 = 5;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageDto {
    pub run_count: u32,
    pub run_limit: Option<u32>,
    pub date: String,
    pub is_free: bool,
}

#[tauri::command]
pub async fn get_usage(state: State<'_, AppState>, app: AppHandle) -> AppResult<UsageDto> {
    let plan = crate::app::license::get_plan(&state.db_pool).await?;
    let date = chrono::Utc::now().format("%Y-%m-%d").to_string();

    if plan != "free" {
        return Ok(UsageDto {
            run_count: 0,
            run_limit: None,
            date,
            is_free: false,
        });
    }

    let token = crate::app::license::get_token(&state.db_pool)
        .await?
        .unwrap_or_default();

    let identity = crate::app::license::machine_id::get_or_create(&app)?;

    let client = reqwest::Client::new();
    let res = client
        .post(format!("{AKIRA_API_URL}/billing/usage"))
        .json(&serde_json::json!({
            "machine_id": identity.id,
            "token": token,
            "action": "check",
            "date": date,
            "created_at_sig": identity.created_at_sig,
        }))
        .send()
        .await
        .map_err(AppError::Http)?;

    let body: serde_json::Value = res.json().await.map_err(AppError::Http)?;

    if let Some(sig) = body["created_at_sig"].as_str() {
        if identity.created_at_sig.as_deref() != Some(sig) {
            let mut updated = identity.clone();
            updated.created_at_sig = Some(sig.to_string());
            let _ = crate::app::license::machine_id::save(&app, &updated);
        }
    }

    let run_count = body["count"].as_u64().unwrap_or(0) as u32;
    let run_limit = body["limit"].as_u64().map(|v| v as u32).unwrap_or(FREE_RUN_LIMIT);

    Ok(UsageDto {
        run_count,
        run_limit: Some(run_limit),
        date,
        is_free: true,
    })
}
