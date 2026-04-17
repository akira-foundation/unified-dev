mod config_dirs;
mod dotenv;
mod env;
mod ollama;
mod shell;

use std::collections::HashSet;

use crate::ai::agents::types::AiProviderKind;

fn kind_key(kind: &AiProviderKind) -> &'static str {
    match kind {
        AiProviderKind::Claude => "claude",
        AiProviderKind::Gemini => "gemini",
        AiProviderKind::OpenAi => "openai",
        AiProviderKind::Copilot => "copilot",
        AiProviderKind::Ollama => "ollama",
    }
}

fn push_unique(
    kind: AiProviderKind,
    seen: &mut HashSet<&'static str>,
    result: &mut Vec<AiProviderKind>,
) {
    let key = kind_key(&kind);
    if seen.insert(key) {
        result.push(kind);
    }
}

pub async fn detect_providers() -> Vec<AiProviderKind> {
    let mut seen = HashSet::new();
    let mut result = Vec::new();

    for kind in env::detect_from_env() {
        push_unique(kind, &mut seen, &mut result);
    }

    for kind in shell::detect_from_shell_config() {
        push_unique(kind, &mut seen, &mut result);
    }

    for kind in dotenv::detect_from_dotenv() {
        push_unique(kind, &mut seen, &mut result);
    }

    for kind in config_dirs::detect_from_config_dirs() {
        push_unique(kind, &mut seen, &mut result);
    }

    if !seen.contains("ollama") {
        if let Some(kind) = ollama::detect_ollama_server().await {
            push_unique(kind, &mut seen, &mut result);
        }
    }

    eprintln!("[detector] Detection complete: {} provider(s) found", result.len());

    result
}
