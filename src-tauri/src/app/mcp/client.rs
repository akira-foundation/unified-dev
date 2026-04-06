use crate::app::support::error::{AppError, AppResult};

const MCP_PROTOCOL_VERSION: &str = "2025-03-26";
const ACCEPT: &str = "application/json, text/event-stream";

fn http_client() -> AppResult<reqwest::Client> {
    reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .map_err(|e| AppError::Internal(e.to_string()))
}

async fn parse_jsonrpc_response(resp: reqwest::Response) -> AppResult<serde_json::Value> {
    let content_type = resp
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_string();

    let body = resp
        .text()
        .await
        .map_err(|e| AppError::Internal(format!("MCP response read error: {e}")))?;

    if content_type.contains("text/event-stream") {
        let data_line = body
            .lines()
            .find(|line| line.starts_with("data:"))
            .map(|line| line[5..].trim().to_string())
            .ok_or_else(|| AppError::Internal("MCP SSE response has no data line".to_string()))?;

        serde_json::from_str(&data_line)
            .map_err(|e| AppError::Internal(format!("MCP SSE JSON parse error: {e}: {data_line}")))
    } else {
        serde_json::from_str(&body)
            .map_err(|e| AppError::Internal(format!("MCP JSON parse error: {e}: {body}")))
    }
}

async fn post_jsonrpc(
    client: &reqwest::Client,
    url: &str,
    token: &str,
    session_id: Option<&str>,
    payload: &serde_json::Value,
) -> AppResult<(serde_json::Value, Option<String>)> {
    let mut req = client
        .post(url)
        .bearer_auth(token)
        .header(reqwest::header::ACCEPT, ACCEPT)
        .header("MCP-Protocol-Version", MCP_PROTOCOL_VERSION)
        .json(payload);

    if let Some(sid) = session_id {
        req = req.header("Mcp-Session-Id", sid);
    }

    let resp = req
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("MCP request failed: {e}")))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("MCP error {status}: {body}")));
    }

    let new_session_id = resp
        .headers()
        .get("Mcp-Session-Id")
        .and_then(|v| v.to_str().ok())
        .map(|s| s.to_string());

    let json = parse_jsonrpc_response(resp).await?;
    Ok((json, new_session_id))
}

async fn post_notification(
    client: &reqwest::Client,
    url: &str,
    token: &str,
    session_id: Option<&str>,
    payload: &serde_json::Value,
) -> AppResult<()> {
    let mut req = client
        .post(url)
        .bearer_auth(token)
        .header(reqwest::header::ACCEPT, ACCEPT)
        .header("MCP-Protocol-Version", MCP_PROTOCOL_VERSION)
        .json(payload);

    if let Some(sid) = session_id {
        req = req.header("Mcp-Session-Id", sid);
    }

    let resp = req
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("MCP notification failed: {e}")))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("MCP notification error {status}: {body}")));
    }

    Ok(())
}

pub async fn list_tools(server_url: &str, token: &str) -> AppResult<Vec<super::types::McpTool>> {
    #[derive(serde::Deserialize)]
    struct RawTool {
        name: String,
        description: Option<String>,
        #[serde(rename = "inputSchema", default = "default_schema")]
        input_schema: serde_json::Value,
    }

    fn default_schema() -> serde_json::Value {
        serde_json::json!({"type": "object", "properties": {}})
    }

    let url = format!("{}/mcp", server_url.trim_end_matches('/'));
    let client = http_client()?;

    let (init_resp, session_id) = post_jsonrpc(
        &client,
        &url,
        token,
        None,
        &serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": { "name": "Unified Dev", "version": "1.0.0" }
            }
        }),
    )
    .await?;

    if let Some(err) = init_resp.get("error") {
        return Err(AppError::Internal(format!("MCP initialize error: {err}")));
    }

    let session_id_ref = session_id.as_deref();

    let _ = post_notification(
        &client,
        &url,
        token,
        session_id_ref,
        &serde_json::json!({
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        }),
    )
    .await;

    let (tools_resp, _) = post_jsonrpc(
        &client,
        &url,
        token,
        session_id_ref,
        &serde_json::json!({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/list",
            "params": {}
        }),
    )
    .await?;

    if let Some(err) = tools_resp.get("error") {
        return Err(AppError::Internal(format!("MCP tools/list error: {err}")));
    }

    let tools: Vec<RawTool> = serde_json::from_value(
        tools_resp["result"]["tools"].clone(),
    )
    .map_err(|e| AppError::Internal(format!("MCP tools parse error: {e}")))?;

    let server_id = server_id_from_url(server_url);

    Ok(tools
        .into_iter()
        .map(|t| super::types::McpTool {
            server_id: server_id.clone(),
            name: t.name,
            description: t.description,
            input_schema: t.input_schema,
        })
        .collect())
}

pub async fn call_tool(
    server_url: &str,
    token: &str,
    tool_name: &str,
    arguments: serde_json::Value,
) -> AppResult<String> {
    let url = format!("{}/mcp", server_url.trim_end_matches('/'));
    let client = http_client()?;

    let (init_resp, session_id) = post_jsonrpc(
        &client,
        &url,
        token,
        None,
        &serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": MCP_PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": { "name": "Unified Dev", "version": "1.0.0" }
            }
        }),
    )
    .await?;

    if let Some(err) = init_resp.get("error") {
        return Err(AppError::Internal(format!("MCP initialize error: {err}")));
    }

    let session_id_ref = session_id.as_deref();

    let _ = post_notification(
        &client,
        &url,
        token,
        session_id_ref,
        &serde_json::json!({
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        }),
    )
    .await;

    let (resp, _) = post_jsonrpc(
        &client,
        &url,
        token,
        session_id_ref,
        &serde_json::json!({
            "jsonrpc": "2.0",
            "id": 2,
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": arguments
            }
        }),
    )
    .await?;

    if let Some(err) = resp.get("error") {
        return Err(AppError::Internal(format!("MCP tools/call error: {err}")));
    }

    let content = resp["result"]["content"]
        .as_array()
        .cloned()
        .unwrap_or_default();

    let text = content
        .into_iter()
        .filter_map(|block| {
            if block["type"] == "text" {
                block["text"].as_str().map(|s| s.to_string())
            } else {
                None
            }
        })
        .collect::<Vec<_>>()
        .join("\n");

    Ok(text)
}

pub fn server_id_from_url(url: &str) -> String {
    reqwest::Url::parse(url)
        .ok()
        .and_then(|u| u.host_str().map(|h| h.replace('.', "-")))
        .unwrap_or_else(|| "mcp".to_string())
}
