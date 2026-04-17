use tauri::{AppHandle, State};

use crate::app::license;
use crate::app::license::types::{ActivateLicenseRequest, CheckoutDto, InvoicesPageDto, LicenseDto};
use crate::app::license::DowngradeDto;
use crate::app::support::error::AppResult;
use crate::state::AppState;

#[tauri::command]
pub async fn checkout_license(plan: String, cycle: String) -> AppResult<CheckoutDto> {
    license::checkout(plan, cycle).await
}

#[tauri::command]
pub async fn activate_license(input: ActivateLicenseRequest, state: State<'_, AppState>, app: AppHandle) -> AppResult<LicenseDto> {
    license::activate(input, &state.db_pool, &app).await
}

#[tauri::command]
pub async fn register_license(token: String, state: State<'_, AppState>, app: AppHandle) -> AppResult<LicenseDto> {
    license::register(token, &state.db_pool, &app).await
}

#[tauri::command]
pub async fn claim_license_request(email: String) -> AppResult<()> {
    license::request_otp(email).await
}

#[tauri::command]
pub async fn claim_license_verify(email: String, otp: String, state: State<'_, AppState>, app: AppHandle) -> AppResult<LicenseDto> {
    license::verify_otp(email, otp, &state.db_pool, &app).await
}

#[tauri::command]
pub async fn get_license(state: State<'_, AppState>) -> AppResult<Option<LicenseDto>> {
    license::get(&state.db_pool).await
}

#[tauri::command]
pub async fn verify_license(state: State<'_, AppState>) -> AppResult<Option<LicenseDto>> {
    license::verify(&state.db_pool).await
}

#[tauri::command]
pub async fn clear_license(state: State<'_, AppState>) -> AppResult<()> {
    license::clear(&state.db_pool).await
}

#[tauri::command]
pub async fn manage_license(state: State<'_, AppState>) -> AppResult<String> {
    let token = license::get_token(&state.db_pool)
        .await?
        .ok_or_else(|| crate::app::support::error::AppError::Internal("No license found".into()))?;
    license::portal(token).await
}

#[tauri::command]
pub async fn downgrade_license(target_plan: String, state: State<'_, AppState>) -> AppResult<DowngradeDto> {
    let token = license::get_token(&state.db_pool)
        .await?
        .ok_or_else(|| crate::app::support::error::AppError::Internal("No license found".into()))?;
    let dto = license::downgrade(token, target_plan).await?;
    license::apply_downgrade(&state.db_pool, &dto).await?;
    Ok(dto)
}

#[tauri::command]
pub async fn list_invoices(cursor: Option<String>, state: State<'_, AppState>) -> AppResult<InvoicesPageDto> {
    let token = license::get_token(&state.db_pool)
        .await?
        .ok_or_else(|| crate::app::support::error::AppError::Internal("No license found".into()))?;
    license::list_invoices(token, cursor).await
}

