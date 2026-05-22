use akira_billing::desktop::{activate_or_refresh, ActivateOrRefreshOptions};
use tauri::State;

use crate::app::billing::PRODUCT_SLUG;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

use super::machine_id;
use super::persist;
use super::signed_license::refresh_public_keys;
use super::types::{ActivateLicenseRequest, LicenseDto};

pub async fn activate(
    input: ActivateLicenseRequest,
    state: State<'_, AppState>,
    app: &tauri::AppHandle,
) -> AppResult<LicenseDto> {
    let identity = machine_id::get_or_create(app)?;

    let verified = {
        let billing = state.billing.read().await;
        let keys = refresh_public_keys(&state.db_pool, billing.inner()).await?;
        activate_or_refresh(
            billing.inner(),
            &ActivateOrRefreshOptions {
                product: PRODUCT_SLUG,
                fingerprint: &identity.id,
                device_type: "desktop",
                platform: Some(std::env::consts::OS),
                device_name: input.device_name.as_deref(),
                app_version: Some(env!("CARGO_PKG_VERSION")),
            },
            &keys,
        )
        .await
        .map_err(|e| translate_billing_error(e, "license_activate"))?
    };

    persist::store_verified(&state.db_pool, &verified).await
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
