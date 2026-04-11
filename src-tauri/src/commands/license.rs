use tauri::State;

use crate::app::license;
use crate::app::license::types::{ActivateLicenseRequest, CheckoutDto, LicenseDto};
use crate::app::support::error::AppResult;
use crate::state::AppState;

#[tauri::command]
pub async fn checkout_license(plan: String, cycle: String) -> AppResult<CheckoutDto> {
    license::checkout(plan, cycle).await
}

#[tauri::command]
pub async fn activate_license(input: ActivateLicenseRequest, state: State<'_, AppState>) -> AppResult<LicenseDto> {
    license::activate(input, &state.db_pool).await
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
