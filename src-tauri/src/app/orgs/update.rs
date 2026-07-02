use tauri::State;

use crate::app::orgs::request::UpdateOrgRequest;
use crate::app::support::error::AppError;
use crate::database::records::OrganizationSummary;
use crate::state::AppState;

pub async fn update(
    state: State<'_, AppState>,
    input: UpdateOrgRequest,
) -> Result<OrganizationSummary, String> {
    if let Some(ref provider_id) = input.provider_id {
        let provider_exists =
            sqlx::query_scalar::<_, i64>("SELECT COUNT(1) FROM providers WHERE id = ?")
                .bind(provider_id)
                .fetch_one(&state.pool().await.map_err(|e| e.to_string())?)
                .await
                .map_err(|e| e.to_string())?;

        if provider_exists == 0 {
            return Err(AppError::Provider("provider not found".to_string()).to_string());
        }
    }

    sqlx::query("UPDATE organizations SET name = ?, provider_id = ? WHERE id = ?")
        .bind(&input.name)
        .bind(&input.provider_id)
        .bind(&input.id)
        .execute(&state.pool().await.map_err(|e| e.to_string())?)
        .await
        .map_err(|e| e.to_string())?;

    sqlx::query_as::<_, OrganizationSummary>(
        r#"
        SELECT
            o.id,
            o.name,
            o.provider_id,
            o.external_id,
            o.created_at,
            COUNT(CASE WHEN r.is_selected = 1 THEN 1 END) AS selected_repos_count,
            ss.updated_at AS last_synced_at
        FROM organizations o
        LEFT JOIN organization_repos r ON r.organization_id = o.id
        LEFT JOIN sync_settings ss ON ss.id = o.id
        WHERE o.id = ?
        GROUP BY o.id
        "#,
    )
    .bind(&input.id)
    .fetch_one(&state.pool().await.map_err(|e| e.to_string())?)
    .await
    .map_err(|e| e.to_string())
}
