pub mod client;
pub mod oauth;
pub mod types;

pub use client::{call_tool, list_tools, server_id_from_url};
pub use oauth::{cancel as cancel_oauth, connect as connect_oauth};
pub use types::{McpServer, McpTool};

use crate::app::support::error::AppResult;
use crate::state::AppState;
use tauri::State;
use chrono::Utc;

pub async fn list(state: State<'_, AppState>) -> AppResult<Vec<McpServer>> {
    let rows = sqlx::query_as::<_, McpServer>(
        "SELECT id, name, url, access_token, token_type, enabled, created_at FROM mcp_servers ORDER BY name COLLATE NOCASE",
    )
    .fetch_all(&state.db_pool)
    .await?;
    Ok(rows)
}

pub async fn add(name: String, url: String, state: State<'_, AppState>) -> AppResult<McpServer> {
    let id = server_id_from_url(&url);
    let now = Utc::now().to_rfc3339();

    sqlx::query(
        "INSERT INTO mcp_servers (id, name, url, access_token, token_type, enabled, created_at)
         VALUES (?, ?, ?, NULL, 'bearer', 1, ?)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, url = excluded.url",
    )
    .bind(&id)
    .bind(&name)
    .bind(&url)
    .bind(&now)
    .execute(&state.db_pool)
    .await?;

    Ok(McpServer { id, name, url, access_token: None, token_type: "bearer".to_string(), enabled: true, created_at: now })
}

pub async fn remove(id: String, state: State<'_, AppState>) -> AppResult<()> {
    sqlx::query("DELETE FROM mcp_servers WHERE id = ?")
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}

pub async fn save_token(id: &str, access_token: &str, token_type: &str, pool: &sqlx::SqlitePool) -> AppResult<()> {
    sqlx::query("UPDATE mcp_servers SET access_token = ?, token_type = ? WHERE id = ?")
        .bind(access_token)
        .bind(token_type)
        .bind(id)
        .execute(pool)
        .await?;
    Ok(())
}

pub async fn set_enabled(id: String, enabled: bool, state: State<'_, AppState>) -> AppResult<()> {
    sqlx::query("UPDATE mcp_servers SET enabled = ? WHERE id = ?")
        .bind(enabled)
        .bind(&id)
        .execute(&state.db_pool)
        .await?;
    Ok(())
}

pub async fn load_servers(pool: &sqlx::SqlitePool) -> Vec<McpServer> {
    sqlx::query_as::<_, McpServer>(
        "SELECT id, name, url, access_token, token_type, enabled, created_at FROM mcp_servers WHERE enabled = 1 AND access_token IS NOT NULL",
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default()
}

pub async fn load_disconnected_servers(pool: &sqlx::SqlitePool) -> Vec<McpServer> {
    sqlx::query_as::<_, McpServer>(
        "SELECT id, name, url, access_token, token_type, enabled, created_at FROM mcp_servers WHERE enabled = 1 AND access_token IS NULL",
    )
    .fetch_all(pool)
    .await
    .unwrap_or_default()
}

pub async fn load_tools(pool: &sqlx::SqlitePool) -> Vec<McpTool> {
    let servers = load_servers(pool).await;

    let mut tools = Vec::new();
    for server in servers {
        let token = server.access_token.unwrap();
        match list_tools(&server.url, &token).await {
            Ok(mut t) => tools.append(&mut t),
            Err(e) => eprintln!("[mcp] tools/list failed for {}: {e}", server.id),
        }
    }
    tools
}
