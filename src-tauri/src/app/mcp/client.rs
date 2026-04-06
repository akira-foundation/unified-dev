use crate::app::support::error::{AppError, AppResult};

fn http_client() -> AppResult<reqwest::Client> {
    reqwest::Client::builder()
        .user_agent("UnifiedDev/1.0")
        .build()
        .map_err(|e| AppError::Internal(e.to_string()))
}

pub async fn list_tools(server_url: &str, token: &str) -> AppResult<Vec<super::types::McpTool>> {
    #[derive(serde::Deserialize)]
    struct ToolsListResponse {
        result: ToolsResult,
    }

    #[derive(serde::Deserialize)]
    struct ToolsResult {
        tools: Vec<RawTool>,
    }

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

    let resp = client
        .post(&url)
        .bearer_auth(token)
        .json(&serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/list",
            "params": {}
        }))
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("MCP tools/list request failed: {e}")))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("MCP tools/list error {status}: {body}")));
    }

    let parsed: ToolsListResponse = resp
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("MCP tools/list parse error: {e}")))?;

    let server_id = server_id_from_url(server_url);

    Ok(parsed
        .result
        .tools
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
    #[derive(serde::Deserialize)]
    struct CallResponse {
        result: CallResult,
    }

    #[derive(serde::Deserialize)]
    struct CallResult {
        content: Vec<ContentBlock>,
    }

    #[derive(serde::Deserialize)]
    #[serde(tag = "type")]
    enum ContentBlock {
        #[serde(rename = "text")]
        Text { text: String },
        #[serde(other)]
        Other,
    }

    let url = format!("{}/mcp", server_url.trim_end_matches('/'));
    let client = http_client()?;

    let resp = client
        .post(&url)
        .bearer_auth(token)
        .json(&serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": {
                "name": tool_name,
                "arguments": arguments
            }
        }))
        .send()
        .await
        .map_err(|e| AppError::Internal(format!("MCP tools/call request failed: {e}")))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(AppError::Internal(format!("MCP tools/call error {status}: {body}")));
    }

    let parsed: CallResponse = resp
        .json()
        .await
        .map_err(|e| AppError::Internal(format!("MCP tools/call parse error: {e}")))?;

    let text = parsed
        .result
        .content
        .into_iter()
        .filter_map(|b| match b {
            ContentBlock::Text { text } => Some(text),
            ContentBlock::Other => None,
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
