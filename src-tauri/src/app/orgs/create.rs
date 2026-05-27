use tauri::State;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::app::orgs::request::CreateOrgRequest;
use crate::app::support::error::AppError;
use crate::database::records::OrganizationSummary;
use crate::state::AppState;

pub async fn create(state: State<'_, AppState>, input: CreateOrgRequest) -> Result<OrganizationSummary, String> {
    let count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM organizations o JOIN providers p ON p.id = o.provider_id",
    )
    .fetch_one(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;
    if !crate::app::license::can_add(&state.db_pool, "orgs", count).await.map_err(|e| e.to_string())? {
        return Err(AppError::FreeTierLimit("org_limit_reached".to_string()).to_string());
    }

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

    let id = Uuid::new_v4().to_string();
    let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();

    sqlx::query(
        "INSERT INTO organizations (id, name, provider_id, external_id, created_at) VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&input.name)
    .bind(&input.provider_id)
    .bind(&input.external_id)
    .bind(&created_at)
    .execute(&state.db_pool)
    .await
    .map_err(|e| e.to_string())?;

    Ok(OrganizationSummary {
        id,
        name: input.name,
        provider_id: Some(input.provider_id),
        external_id: input.external_id,
        created_at,
        selected_repos_count: 0,
        last_synced_at: None,
    })
}
