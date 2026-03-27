use tauri::State;

use crate::app::support::error::AppResult;
use crate::state::AppState;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VisibilityPreferencesDto {
    pub scope_type: String,
    pub scope_id: String,
    pub issue_scope: String,
    pub pr_scope: String,
    pub assign_issues_to_self: bool,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpsertVisibilityPreferencesRequest {
    pub scope_type: String,
    pub scope_id: String,
    pub issue_scope: String,
    pub pr_scope: String,
    pub assign_issues_to_self: bool,
}

pub async fn get(
    scope_type: String,
    scope_id: String,
    state: State<'_, AppState>,
) -> AppResult<VisibilityPreferencesDto> {
    let row = sqlx::query_as::<_, (String, String, String, String, i64)>(
        "SELECT scope_type, scope_id, issue_scope, pr_scope, assign_issues_to_self FROM visibility_preferences WHERE scope_type = ? AND scope_id = ?",
    )
    .bind(&scope_type)
    .bind(&scope_id)
    .fetch_optional(&state.db_pool)
    .await?;

    Ok(match row {
        Some((scope_type, scope_id, issue_scope, pr_scope, assign_issues_to_self)) => VisibilityPreferencesDto {
            scope_type,
            scope_id,
            issue_scope,
            pr_scope,
            assign_issues_to_self: assign_issues_to_self != 0,
        },
        None => VisibilityPreferencesDto {
            scope_type,
            scope_id,
            issue_scope: "my_queue".to_string(),
            pr_scope: "mine_or_review_requested".to_string(),
            assign_issues_to_self: true,
        },
    })
}

pub async fn upsert(
    input: UpsertVisibilityPreferencesRequest,
    state: State<'_, AppState>,
) -> AppResult<VisibilityPreferencesDto> {
    let now = chrono::Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO visibility_preferences (scope_type, scope_id, issue_scope, pr_scope, assign_issues_to_self, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(scope_type, scope_id) DO UPDATE SET
           issue_scope = excluded.issue_scope,
           pr_scope = excluded.pr_scope,
           assign_issues_to_self = excluded.assign_issues_to_self,
           updated_at = excluded.updated_at"
    )
    .bind(&input.scope_type)
    .bind(&input.scope_id)
    .bind(&input.issue_scope)
    .bind(&input.pr_scope)
    .bind(input.assign_issues_to_self as i64)
    .bind(&now)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;

    Ok(VisibilityPreferencesDto {
        scope_type: input.scope_type,
        scope_id: input.scope_id,
        issue_scope: input.issue_scope,
        pr_scope: input.pr_scope,
        assign_issues_to_self: input.assign_issues_to_self,
    })
}

pub async fn reset(
    scope_type: String,
    scope_id: String,
    state: State<'_, AppState>,
) -> AppResult<VisibilityPreferencesDto> {
    sqlx::query("DELETE FROM visibility_preferences WHERE scope_type = ? AND scope_id = ?")
        .bind(&scope_type)
        .bind(&scope_id)
        .execute(&state.db_pool)
        .await?;

    get(scope_type, scope_id, state).await
}
