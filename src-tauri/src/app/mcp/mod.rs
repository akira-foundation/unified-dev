pub mod client;
pub mod oauth;
pub mod types;

pub use client::{call_tool, list_tools, server_id_from_url};
pub use oauth::{cancel as cancel_oauth, connect as connect_oauth};
pub use types::{McpServer, McpTool};

use crate::app::support::error::AppResult;
use crate::state::AppState;
use chrono::Utc;
use tauri::State;

pub async fn list(state: State<'_, AppState>) -> AppResult<Vec<McpServer>> {
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    let rows = sqlx::query_as::<_, McpServer>(
        "SELECT id, name, url, access_token, token_type, enabled, created_at FROM mcp_servers WHERE customer_id = ? ORDER BY name COLLATE NOCASE",
    )
    .bind(&customer_id)
    .fetch_all(&state.pool().await?)
    .await?;
    Ok(rows)
}

pub async fn add(name: String, url: String, state: State<'_, AppState>) -> AppResult<McpServer> {
    let id = server_id_from_url(&url);
    let now = Utc::now().to_rfc3339();
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;

    sqlx::query(
        "INSERT INTO mcp_servers (id, name, url, access_token, token_type, enabled, created_at, customer_id)
         VALUES (?, ?, ?, NULL, 'bearer', 1, ?, ?)
         ON CONFLICT(id, customer_id) DO UPDATE SET name = excluded.name, url = excluded.url",
    )
    .bind(&id)
    .bind(&name)
    .bind(&url)
    .bind(&now)
    .bind(&customer_id)
    .execute(&state.pool().await?)
    .await?;

    Ok(McpServer {
        id,
        name,
        url,
        access_token: None,
        token_type: "bearer".to_string(),
        enabled: true,
        created_at: now,
    })
}

pub async fn remove(id: String, state: State<'_, AppState>) -> AppResult<()> {
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    sqlx::query("DELETE FROM mcp_servers WHERE id = ? AND customer_id IS ?")
        .bind(&id)
        .bind(&customer_id)
        .execute(&state.pool().await?)
        .await?;
    Ok(())
}

pub async fn save_token(
    id: &str,
    access_token: &str,
    token_type: &str,
    pool: &sqlx::SqlitePool,
) -> AppResult<()> {
    let customer_id = crate::app::auth::current_customer_id(pool).await;
    sqlx::query(
        "UPDATE mcp_servers SET access_token = ?, token_type = ? WHERE id = ? AND customer_id IS ?",
    )
    .bind(access_token)
    .bind(token_type)
    .bind(id)
    .bind(&customer_id)
    .execute(pool)
    .await?;
    Ok(())
}

pub async fn set_enabled(id: String, enabled: bool, state: State<'_, AppState>) -> AppResult<()> {
    let customer_id = crate::app::auth::current_customer_id(&state.pool().await?).await;
    sqlx::query("UPDATE mcp_servers SET enabled = ? WHERE id = ? AND customer_id IS ?")
        .bind(enabled)
        .bind(&id)
        .bind(&customer_id)
        .execute(&state.pool().await?)
        .await?;
    Ok(())
}

pub async fn load_servers(pool: &sqlx::SqlitePool) -> Vec<McpServer> {
    let customer_id = crate::app::auth::current_customer_id(pool).await;
    sqlx::query_as::<_, McpServer>(
        "SELECT id, name, url, access_token, token_type, enabled, created_at FROM mcp_servers WHERE enabled = 1 AND access_token IS NOT NULL AND customer_id = ?",
    )
    .bind(&customer_id)
    .fetch_all(pool)
    .await
    .unwrap_or_default()
}

pub async fn load_disconnected_servers(pool: &sqlx::SqlitePool) -> Vec<McpServer> {
    let customer_id = crate::app::auth::current_customer_id(pool).await;
    sqlx::query_as::<_, McpServer>(
        "SELECT id, name, url, access_token, token_type, enabled, created_at FROM mcp_servers WHERE enabled = 1 AND access_token IS NULL AND customer_id = ?",
    )
    .bind(&customer_id)
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
