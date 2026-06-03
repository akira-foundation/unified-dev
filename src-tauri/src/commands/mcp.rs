use tauri::{AppHandle, State};

use crate::app::mcp;
use crate::app::mcp::McpServer;
use crate::app::support::error::AppResult;
use crate::state::AppState;

#[tauri::command]
pub async fn list_mcp_servers(state: State<'_, AppState>) -> AppResult<Vec<McpServer>> {
    mcp::list(state).await
}

#[tauri::command]
pub async fn add_mcp_server(name: String, url: String, state: State<'_, AppState>) -> AppResult<McpServer> {
    mcp::add(name, url, state).await
}

#[tauri::command]
pub async fn remove_mcp_server(id: String, state: State<'_, AppState>) -> AppResult<()> {
    mcp::remove(id, state).await
}

#[tauri::command]
pub async fn set_mcp_server_enabled(id: String, enabled: bool, state: State<'_, AppState>) -> AppResult<()> {
    mcp::set_enabled(id, enabled, state).await
}

#[tauri::command]
pub async fn connect_mcp_server(
    id: String,
    app: AppHandle,
    state: State<'_, AppState>,
) -> AppResult<()> {
    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    let server = sqlx::query_as::<_, McpServer>(
        "SELECT id, name, url, access_token, token_type, enabled, created_at FROM mcp_servers WHERE id = ? AND customer_id IS ?",
    )
    .bind(&id)
    .bind(&customer_id)
    .fetch_optional(&state.db_pool)
    .await?
    .ok_or_else(|| crate::app::support::error::AppError::Internal(format!("MCP server '{id}' not found")))?;

    let result = mcp::connect_oauth(&server.url, &app).await?;
    mcp::save_token(&id, &result.access_token, &result.token_type, &state.db_pool).await?;
    Ok(())
}

#[tauri::command]
pub async fn disconnect_mcp_server(id: String, state: State<'_, AppState>) -> AppResult<()> {
    let customer_id = crate::app::auth::current_customer_id(&state.db_pool).await;
    sqlx::query("UPDATE mcp_servers SET access_token = NULL WHERE id = ? AND customer_id IS ?")
        .bind(&id)
        .bind(&customer_id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}

#[tauri::command]
pub async fn cancel_mcp_connect() {
    mcp::cancel_oauth().await;
}
