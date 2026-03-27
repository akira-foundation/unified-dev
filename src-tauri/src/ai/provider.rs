use async_trait::async_trait;
use tauri::AppHandle;

use crate::app::chat::message::Message;
use crate::app::support::error::AppResult;

/// Encapsulates everything a provider needs to generate a completion.
pub struct AiRequest {
    pub thread_id: String,
    pub system_prompt: String,
    /// The current user message to send. Always appended after `history`.
    pub content: String,
    pub history: Vec<Message>,
    pub model: String,
    pub workspace_path: String,
    pub plan_mode: bool,
    /// One of "x-high", "high", "medium", "low".
    pub thinking_budget: String,
    pub fast_mode: bool,
}

/// A pluggable AI provider adapter.
#[async_trait]
pub trait AiProvider: Send + Sync {
    /// Short identifier (e.g. "anthropic", "copilot_chat").
    fn id(&self) -> &str;

    /// Returns true when this adapter should handle `model`.
    fn supports_model(&self, model: &str) -> bool;

    /// Run the full agentic loop and return the final assistant text.
    async fn complete(&self, request: AiRequest, app: &AppHandle) -> AppResult<String>;
}
