use tauri::State;
use time::format_description::well_known::Rfc3339;
use time::OffsetDateTime;
use uuid::Uuid;

use crate::app::providers::request::CreateProviderRequest;
use crate::database::records::ProviderRecord;
use crate::database::records::ProviderSummary;
use crate::state::AppState;

pub async fn create(state: State<'_, AppState>, input: CreateProviderRequest) -> Result<ProviderSummary, String> {
    let id = Uuid::new_v4().to_string();
    let created_at = OffsetDateTime::now_utc().format(&Rfc3339).unwrap_or_default();
    let (auth_type, auth_payload) = crate::app::providers::credentials::serialize_auth(&state, &input.auth)
        .map_err(|error| error.to_string())?;

    let provider = ProviderRecord {
        id,
        name: input.name,
        kind: input.kind,
        auth_type,
        auth_payload,
        created_at,
        account_login: input.account_login,
        account_type: input.account_type,
    };

    state.provider_repo.create(&provider).await.map_err(|error| error.to_string())
}
