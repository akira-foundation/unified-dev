use tauri::AppHandle;

use crate::ai::provider::AiProvider;
use crate::ai::adapters::anthropic::AnthropicAdapter;
use crate::ai::adapters::claude_cli::ClaudeCliAdapter;
use crate::ai::adapters::codex::CodexAdapter;
use crate::ai::adapters::codex_cli::CodexCliAdapter;
use crate::ai::adapters::copilot_chat::CopilotChatAdapter;
use crate::ai::adapters::copilot_responses::CopilotResponsesAdapter;
use crate::ai::credentials::{
    read_codex_access_token, read_copilot_oauth_token, resolve_env_key,
};
use crate::ai::provider::AiRequest;
use crate::error::{AppError, AppResult};

/// Routes a request to the correct adapter, applying fallback logic.
pub async fn dispatch(request: AiRequest, app: &AppHandle) -> AppResult<String> {
    let model = request.model.clone();

    // Claude family: Anthropic API → Claude CLI → Copilot Chat → Codex direct
    if model.starts_with("claude-") {
        if resolve_env_key("ANTHROPIC_API_KEY").is_some() {
            return AnthropicAdapter.complete(request, app).await;
        }
        if find_claude_cli_available() {
            eprintln!("[registry] ANTHROPIC_API_KEY not found, falling back to Claude CLI");
            return ClaudeCliAdapter.complete(request, app).await;
        }
        if read_copilot_oauth_token().is_some() {
            eprintln!("[registry] Claude CLI not found, falling back to GitHub Copilot");
            return CopilotChatAdapter.complete(request, app).await;
        }
        if read_codex_access_token().is_some() {
            eprintln!("[registry] Copilot not available, falling back to OpenAI Codex direct");
            return CodexAdapter.complete(request, app).await;
        }
        return Err(AppError::Internal(
            "No AI provider available. Set ANTHROPIC_API_KEY in your shell config, install the Claude CLI, or install GitHub Copilot / OpenAI Codex CLI.".to_string(),
        ));
    }

    // gpt-5.x / codex-*: Copilot Responses API → Codex CLI
    if model.starts_with("gpt-5") || model.starts_with("codex-") {
        if read_copilot_oauth_token().is_some() {
            let result = CopilotResponsesAdapter.complete(request, app).await;
            return result;
        }
        eprintln!("[registry] Copilot credentials not found, trying codex CLI for {model}");
        return CodexCliAdapter.complete(request, app).await;
    }

    // Everything else (gpt-4*, o1/o3/o4, gemini-*, grok-*, copilot-*): Copilot Chat
    if CopilotChatAdapter.supports_model(&model) {
        if read_copilot_oauth_token().is_some() {
            return CopilotChatAdapter.complete(request, app).await;
        }
        return Err(AppError::Internal(
            "GitHub Copilot credentials not found. Make sure the Copilot extension is installed and authenticated.".to_string(),
        ));
    }

    // Ollama / unknown: stub
    let placeholder = format!("[Model '{model}' is not yet supported]");
    Err(AppError::Internal(placeholder))
}

fn find_claude_cli_available() -> bool {
    let home = dirs::home_dir();
    let mut candidates: Vec<std::path::PathBuf> = vec![
        std::path::PathBuf::from("/usr/local/bin/claude"),
        std::path::PathBuf::from("/opt/homebrew/bin/claude"),
    ];
    if let Some(ref h) = home {
        candidates.insert(0, h.join(".local/bin/claude"));
    }
    if let Ok(path_var) = std::env::var("PATH") {
        for dir in path_var.split(':') {
            candidates.push(std::path::PathBuf::from(dir).join("claude"));
        }
    }
    candidates.into_iter().any(|p| p.exists())
}
