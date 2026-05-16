use serde::Serialize;
use tauri::State;

use crate::app::billing::PRODUCT_SLUG;
use crate::app::support::error::{AppError, AppResult};
use crate::state::AppState;

#[derive(Debug, Clone, Serialize)]
pub struct ProductPlansDto {
    pub product: String,
    pub name: String,
    pub description: Option<String>,
    pub landing_url: Option<String>,
    pub beta_ends_at: Option<String>,
    pub beta_active: bool,
    pub plans: Vec<PlanDto>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PlanDto {
    pub id: String,
    pub key: String,
    pub name: String,
    pub description: Option<String>,
    pub amount: Option<i64>,
    pub currency: Option<String>,
    pub billing_interval: Option<String>,
    pub trial_period_days: u32,
    pub is_coming_soon: bool,
    pub features: Vec<PlanFeatureDto>,
}

#[derive(Debug, Clone, Serialize)]
pub struct PlanFeatureDto {
    pub key: String,
    pub name: String,
    pub description: Option<String>,
}

pub async fn list(state: State<'_, AppState>) -> AppResult<ProductPlansDto> {
    let response = {
        let billing = state.billing.read().await;
        billing
            .inner()
            .plans()
            .await
            .map_err(|error| AppError::Internal(format!("plans request failed: {error}")))?
    };

    let _ = PRODUCT_SLUG;

    Ok(ProductPlansDto {
        product: response.product,
        name: response.name,
        description: response.description,
        landing_url: response.landing_url,
        beta_ends_at: response.beta_ends_at,
        beta_active: response.beta_active,
        plans: response
            .plans
            .into_iter()
            .map(|plan| PlanDto {
                id: plan.id,
                key: plan.key,
                name: plan.name,
                description: plan.description,
                amount: plan.amount,
                currency: plan.currency,
                billing_interval: plan.billing_interval,
                trial_period_days: plan.trial_period_days,
                is_coming_soon: plan.is_coming_soon,
                features: plan
                    .features
                    .into_iter()
                    .map(|feature| PlanFeatureDto {
                        key: feature.key,
                        name: feature.name,
                        description: feature.description,
                    })
                    .collect(),
            })
            .collect(),
    })
}
