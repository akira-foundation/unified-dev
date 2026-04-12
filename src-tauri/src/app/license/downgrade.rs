use crate::app::support::error::{AppError, AppResult};
use serde::{Deserialize, Serialize};

const AKIRA_API_URL: &str = env!("AKIRA_API_URL");

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub struct DowngradeDto {
    pub cancel_at_period_end: bool,
    pub cancel_at: Option<String>,
    pub plan: Option<String>,
    pub valid_until: Option<String>,
    pub signature: Option<String>,
    pub target_plan: Option<String>,
}

pub async fn downgrade(token: String, target_plan: String) -> AppResult<DowngradeDto> {
    let client = reqwest::Client::new();
    let res = client
        .post(format!("{AKIRA_API_URL}/billing/downgrade"))
        .header("Content-Type", "application/json")
        .json(&serde_json::json!({ "token": token, "target_plan": target_plan }))
        .send()
        .await
        .map_err(AppError::Http)?;

    if !res.status().is_success() {
        let msg = res.text().await.unwrap_or_default();
        let error_code = serde_json::from_str::<serde_json::Value>(&msg)
            .ok()
            .and_then(|v| v["error"].as_str().map(str::to_string))
            .unwrap_or_else(|| msg.clone());
        return Err(AppError::Internal(error_code));
    }

    let dto: DowngradeDto = res.json().await.map_err(AppError::Http)?;
    Ok(dto)
}

pub async fn apply_downgrade(pool: &sqlx::SqlitePool, dto: &DowngradeDto) -> AppResult<()> {
    sqlx::query(
        "UPDATE license SET cancel_at_period_end = ?, cancel_at = ?, target_plan = ? WHERE id = 'local'",
    )
    .bind(dto.cancel_at_period_end)
    .bind(dto.cancel_at.as_deref())
    .bind(dto.target_plan.as_deref())
    .execute(pool)
    .await?;
    Ok(())
}
