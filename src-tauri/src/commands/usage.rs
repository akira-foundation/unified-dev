use akira_billing::types::UsagePayload;
use serde::Serialize;
use tauri::State;

use crate::app::billing::PRODUCT_SLUG;
use crate::app::license;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

const DEFAULT_FEATURE: &str = "agent_run";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UsageDto {
    pub run_count: u32,
    pub run_limit: Option<u32>,
    pub date: String,
    pub is_free: bool,
}

#[tauri::command]
pub async fn get_usage(state: State<'_, AppState>) -> AppResult<UsageDto> {
    check_feature(&state, DEFAULT_FEATURE).await
}

#[tauri::command]
pub async fn get_feature_usage(feature: String, state: State<'_, AppState>) -> AppResult<UsageDto> {
    check_feature(&state, &feature).await
}

async fn check_feature(state: &State<'_, AppState>, feature: &str) -> AppResult<UsageDto> {
    let plan = license::get_plan(&state.db_pool).await?;
    let date = chrono::Utc::now().format("%Y-%m-%d").to_string();

    if plan != "free" {
        return Ok(UsageDto {
            run_count: 0,
            run_limit: None,
            date,
            is_free: false,
        });
    }

    let fingerprint = license::device_fingerprint();
    let has_token = license::load_customer_token(&state.db_pool, &state.token_cipher)
        .await?
        .is_some();
    let platform = std::env::consts::OS;
    let app_version = env!("CARGO_PKG_VERSION");
    let payload = UsagePayload {
        product: PRODUCT_SLUG,
        feature,
        date: &date,
        device_fp: &fingerprint,
        action: "check",
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

    Ok(UsageDto {
        run_count: response.count,
        run_limit: response.limit,
        date,
        is_free: true,
    })
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
