use tauri::State;

use crate::app::providers::request::CreateProviderRequest;
use crate::database::records::{ProviderRecord, ProviderSummary};
use crate::state::AppState;

pub async fn create(
    state: State<'_, AppState>,
    input: CreateProviderRequest,
) -> Result<ProviderSummary, String> {
    let id = uuid::Uuid::new_v4().to_string();
    let created_at = time::OffsetDateTime::now_utc()
        .format(&time::format_description::well_known::Rfc3339)
        .unwrap_or_default();
    let (auth_type, auth_payload) =
        crate::app::providers::credentials::serialize_auth(&state, &input.auth)
            .map_err(|e| e.to_string())?;

    let record = ProviderRecord {
        id: id.clone(),
        name: input.name.clone(),
        kind: input.kind.clone(),
        auth_type,
        auth_payload,
        created_at: created_at.clone(),
        account_login: input.account_login.clone(),
        account_type: input.account_type.clone(),
    };

    sqlx::query(
        "INSERT INTO providers (id, name, kind, auth_type, auth_payload, created_at, account_login, account_type) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&record.id)
    .bind(&record.name)
    .bind(&record.kind)
    .bind(&record.auth_type)
    .bind(&record.auth_payload)
    .bind(&record.created_at)
    .bind(&record.account_login)
    .bind(&record.account_type)
    .execute(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())?;

    Ok(ProviderSummary {
        id,
        name: input.name,
        kind: input.kind,
        auth_type: record.auth_type,
        created_at,
        account_login: input.account_login,
        account_type: input.account_type,
    })
}
