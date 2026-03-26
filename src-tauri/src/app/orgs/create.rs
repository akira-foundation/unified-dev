use tauri::State;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::app::orgs::request::CreateOrgRequest;
use crate::database::models::OrganizationRecord;
use crate::database::models::OrganizationSummary;
use crate::app::support::error::AppError;
use crate::state::AppState;

pub async fn create(state: State<'_, AppState>, input: CreateOrgRequest) -> Result<OrganizationSummary, String> {
    let provider_exists = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(1) FROM providers WHERE id = ?",
    )
    .bind(&input.provider_id)
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    if provider_exists == 0 {
        return Err(AppError::Provider("provider not found".to_string()).to_string());
    }

    let organization = OrganizationRecord {
        id: Uuid::new_v4().to_string(),
        name: input.name,
        provider_id: Some(input.provider_id),
        external_id: input.external_id,
        created_at: OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default(),
    };

    sqlx::query(
        "INSERT INTO organizations (id, name, provider_id, external_id, created_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&organization.id)
    .bind(&organization.name)
    .bind(&organization.provider_id)
    .bind(&organization.external_id)
    .bind(&organization.created_at)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(OrganizationSummary {
        id: organization.id,
        name: organization.name,
        provider_id: organization.provider_id,
        external_id: organization.external_id,
        created_at: organization.created_at,
    })
}
