use std::sync::Arc;

use tauri::AppHandle;

use crate::ai::credentials::{read_codex_access_token, read_copilot_oauth_token, resolve_env_key};
use crate::ai::provider::{AiProvider, AiRequest};
use crate::ai::providers::anthropic::find_claude_cli;
use crate::error::{AppError, AppResult};

pub struct AiRegistry {
    providers: Vec<Arc<dyn AiProvider>>,
}

impl AiRegistry {
    pub fn new() -> Self {
        Self { providers: Vec::new() }
    }

    pub fn register(&mut self, provider: Arc<dyn AiProvider>) {
        self.providers.push(provider);
    }

    fn find(&self, id: &str) -> Option<&Arc<dyn AiProvider>> {
        self.providers.iter().find(|p| p.id() == id)
    }

    /// Routes a request to the correct provider, applying fallback logic.
    pub async fn dispatch(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        let model = request.model.clone();

        if model.starts_with("claude-") {
            if resolve_env_key("ANTHROPIC_API_KEY").is_some() {
                return self.find("anthropic").unwrap().complete(request, app).await;
            }
            if find_claude_cli().is_some() {
                eprintln!("[registry] ANTHROPIC_API_KEY not found, falling back to Claude CLI");
                return self.find("anthropic_cli").unwrap().complete(request, app).await;
            }
            if read_copilot_oauth_token().is_some() {
                eprintln!("[registry] Claude CLI not found, falling back to GitHub Copilot");
                return self.find("copilot_chat").unwrap().complete(request, app).await;
            }
            if read_codex_access_token().is_some() {
                eprintln!("[registry] Copilot not available, falling back to OpenAI direct");
                return self.find("openai").unwrap().complete(request, app).await;
            }
            return Err(AppError::Internal(
                "No AI provider available. Set ANTHROPIC_API_KEY in your shell config, install the Claude CLI, or install GitHub Copilot / OpenAI Codex CLI.".to_string(),
            ));
        }

        if model.starts_with("gpt-5") || model.starts_with("codex-") {
            if read_copilot_oauth_token().is_some() {
                return self.find("copilot_responses").unwrap().complete(request, app).await;
            }
            eprintln!("[registry] Copilot credentials not found, trying codex CLI for {model}");
            return self.find("openai_cli").unwrap().complete(request, app).await;
        }

        if let Some(provider) = self.providers.iter().find(|p| p.supports_model(&model)) {
            if read_copilot_oauth_token().is_some() {
                return provider.complete(request, app).await;
            }
            return Err(AppError::Internal(
                "GitHub Copilot credentials not found. Make sure the Copilot extension is installed and authenticated.".to_string(),
            ));
        }

        Err(AppError::Internal(format!("[Model '{model}' is not yet supported]")))
    }
}
