use tauri::State;

use crate::db::inputs::UpdateOrganizationInput;
use crate::db::models::OrganizationSummary;
use crate::support::error::AppError;
use crate::state::AppState;

pub async fn update_organization(state: State<'_, AppState>, input: UpdateOrganizationInput) -> Result<OrganizationSummary, String> {
    if let Some(ref provider_id) = input.provider_id {
        let provider_exists = sqlx::query_scalar::<_, i64>(
            "SELECT COUNT(1) FROM providers WHERE id = ?",
        )
        .bind(provider_id)
        .fetch_one(&state.db_pool)
        .await
        .map_err(|e| e.to_string())?;

        if provider_exists == 0 {
            return Err(AppError::Provider("provider not found".to_string()).to_string());
        }
    }

    sqlx::query(
        "UPDATE organizations SET name = ?, provider_id = ? WHERE id = ?",
    )
    .bind(&input.name)
    .bind(&input.provider_id)
    .bind(&input.id)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    sqlx::query_as::<_, OrganizationSummary>(
        "SELECT id, name, provider_id, external_id, created_at FROM organizations WHERE id = ?",
    )
    .bind(&input.id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())
}
