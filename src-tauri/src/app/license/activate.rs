use akira_billing::types::LicenseActivatePayload;
use tauri::State;

use crate::app::billing::PRODUCT_SLUG;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

use super::machine_id;
use super::persist;
use super::types::{ActivateLicenseRequest, LicenseDto};

pub async fn activate(
    input: ActivateLicenseRequest,
    state: State<'_, AppState>,
    app: &tauri::AppHandle,
) -> AppResult<LicenseDto> {
    let identity = machine_id::get_or_create(app)?;
    let platform = std::env::consts::OS;
    let app_version = env!("CARGO_PKG_VERSION");
    let device_name = input.device_name.as_deref();

    let response = {
        let billing = state.billing.read().await;
        billing
            .inner()
            .license_activate(LicenseActivatePayload {
                product: PRODUCT_SLUG,
                device_type: "desktop",
                platform: Some(platform),
                device_name,
                app_version: Some(app_version),
                fingerprint: &identity.id,
            })
            .await
            .map_err(|e| translate_billing_error(e, "license_activate"))?
    };

    persist::store_activation(&state.db_pool, &response, &identity.id).await
}

fn translate_billing_error(err: akira_billing::Error, context: &str) -> AppError {
    use akira_billing::Error as BErr;
    match err {
        BErr::Api { status, code } => {
            if !code.is_empty() {
                AppError::Internal(code)
            } else {
                AppError::Internal(format!("billing {context} failed: HTTP {status}"))
            }
        }
        other => AppError::Internal(format!("billing {context}: {other}")),
    }
}
