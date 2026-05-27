use tauri::State;

use crate::app::license;
use crate::app::license::plans::ProductPlansDto;
use crate::app::license::types::{ActivateLicenseRequest, InvoicesPageDto, LicenseDto};
use crate::app::license::DowngradeDto;
use crate::app::support::error::AppResult;
use crate::state::AppState;

#[tauri::command]
pub fn checkout_url(plan_key: String) -> String {
    license::checkout_url(&plan_key)
}

#[tauri::command]
pub async fn get_product_plans(state: State<'_, AppState>) -> AppResult<ProductPlansDto> {
    license::plans::list(state).await
}

#[tauri::command]
pub async fn activate_license(input: ActivateLicenseRequest, state: State<'_, AppState>) -> AppResult<LicenseDto> {
    license::activate(input, state).await
}

#[tauri::command]
pub async fn claim_license_request(email: String, state: State<'_, AppState>) -> AppResult<()> {
    license::request_otp(email, state).await
}

#[tauri::command]
pub async fn claim_license_verify(email: String, otp: String, state: State<'_, AppState>) -> AppResult<LicenseDto> {
    license::verify_otp(email, otp, state).await
}

#[tauri::command]
pub async fn get_license(state: State<'_, AppState>) -> AppResult<Option<LicenseDto>> {
    license::get(&state.db_pool).await
}

#[tauri::command]
pub async fn verify_license(state: State<'_, AppState>) -> AppResult<Option<LicenseDto>> {
    let fingerprint = license::device_fingerprint();
    let billing = state.billing.read().await.clone();
    license::verify(&state.db_pool, &billing, &fingerprint).await
}

#[tauri::command]
pub async fn clear_license(state: State<'_, AppState>) -> AppResult<()> {
    license::clear(&state.db_pool).await
}

#[tauri::command]
pub async fn manage_license(state: State<'_, AppState>) -> AppResult<String> {
    let billing = state.billing.read().await.clone();
    license::portal(&billing).await
}

#[tauri::command]
pub async fn downgrade_license(target_plan: String, state: State<'_, AppState>) -> AppResult<DowngradeDto> {
    let billing = state.billing.read().await.clone();
    let dto = license::downgrade(&billing, target_plan).await?;
    license::apply_downgrade(&state.db_pool, &dto).await?;
    Ok(dto)
}

#[tauri::command]
pub async fn resume_license(state: State<'_, AppState>) -> AppResult<DowngradeDto> {
    let billing = state.billing.read().await.clone();
    let dto = license::resume(&billing).await?;
    license::apply_downgrade(&state.db_pool, &dto).await?;
    Ok(dto)
}

#[tauri::command]
pub async fn list_invoices(cursor: Option<String>, state: State<'_, AppState>) -> AppResult<InvoicesPageDto> {
    let billing = state.billing.read().await.clone();
    license::list_invoices(&billing, cursor).await
}

