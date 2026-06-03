use std::sync::Arc;

use tauri::AppHandle;

use crate::ai::credentials::{read_copilot_oauth_token, resolve_env_key};
use crate::ai::provider::{AiProvider, AiRequest};
use crate::ai::providers::anthropic::find_claude_cli;
use crate::ai::providers::google::{find_gemini_cli, has_gemini_credentials};
use crate::app::support::error::{AppError, AppResult};

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

    pub async fn dispatch(&self, request: AiRequest, app: &AppHandle) -> AppResult<String> {
        let model = request.model.clone();

        if let Some(inner_model) = model.strip_prefix("copilot:") {
            if read_copilot_oauth_token().is_some() {
                let mut req = request;
                req.model = inner_model.to_string();
                return self.find("copilot_chat").unwrap().complete(req, app).await;
            }
            return Err(AppError::Internal(
                "GitHub Copilot credentials not found. Make sure the Copilot extension is installed and authenticated.".to_string(),
            ));
        }

        if model.starts_with("claude-") {
            let id = select_anthropic_provider(
                find_claude_cli().is_some(),
                resolve_env_key("ANTHROPIC_API_KEY").is_some(),
            )?;
            return self.find(id).unwrap().complete(request, app).await;
        }

        if model.starts_with("gpt-5") || model.starts_with("codex-") {
            if read_copilot_oauth_token().is_some() {
                return self.find("copilot_responses").unwrap().complete(request, app).await;
            }
            return self.find("openai_cli").unwrap().complete(request, app).await;
        }

        if model.starts_with("gemini-") || model.starts_with("auto-gemini-") {
            if find_gemini_cli().is_some() && has_gemini_credentials() {
                return self.find("gemini_cli").unwrap().complete(request, app).await;
            }
            return Err(AppError::Internal(
                "Gemini CLI not found or not authenticated. Install it with: brew install gemini-cli".to_string(),
            ));
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

fn select_anthropic_provider(has_claude_cli: bool, has_api_key: bool) -> AppResult<&'static str> {
    if has_claude_cli {
        return Ok("anthropic_cli");
    }
    if has_api_key {
        return Ok("anthropic");
    }
    Err(AppError::Internal(
        "No Anthropic provider available. Install Claude Code (the `claude` CLI) and sign in, or set ANTHROPIC_API_KEY in your shell config.".to_string(),
    ))
}

#[cfg(test)]
mod tests {
    use super::select_anthropic_provider;

    #[test]
    fn prefers_claude_cli_over_api_key() {
        assert_eq!(select_anthropic_provider(true, true).unwrap(), "anthropic_cli");
    }

    #[test]
    fn uses_claude_cli_when_no_api_key() {
        assert_eq!(select_anthropic_provider(true, false).unwrap(), "anthropic_cli");
    }

    #[test]
    fn falls_back_to_api_key_without_cli() {
        assert_eq!(select_anthropic_provider(false, true).unwrap(), "anthropic");
    }

    #[test]
    fn errors_when_neither_available() {
        assert!(select_anthropic_provider(false, false).is_err());
    }
}
