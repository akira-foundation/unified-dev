use async_trait::async_trait;
use tauri::AppHandle;

use crate::app::chat::message::Message;
use crate::app::mcp::{McpServer, McpTool};
use crate::app::support::error::AppResult;

pub struct AiRequest {
    pub thread_id: String,
    pub system_prompt: String,
    pub content: String,
    pub history: Vec<Message>,
    pub model: String,
    pub workspace_path: String,
    pub plan_mode: bool,
    pub thinking_budget: String,
    pub fast_mode: bool,
    pub mcp_tools: Vec<McpTool>,
    pub mcp_servers: Vec<McpServer>,
    pub mcp_disconnected_servers: Vec<McpServer>,
}

#[async_trait]
pub trait AiProvider: Send + Sync {
    fn id(&self) -> &str;
    fn supports_model(&self, model: &str) -> bool;
    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String>;
}
