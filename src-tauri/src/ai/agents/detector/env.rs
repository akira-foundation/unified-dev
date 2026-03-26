use std::env;

use crate::ai::agents::types::AiProviderKind;

const ANTHROPIC_KEY: &str = "ANTHROPIC_API_KEY";
const OPENAI_KEY: &str = "OPENAI_API_KEY";

pub fn detect_from_env() -> Vec<AiProviderKind> {
    let mut found = Vec::new();

    if env::var(ANTHROPIC_KEY).is_ok() {
        eprintln!("[detector] Detected provider: Claude (environment variable)");
        found.push(AiProviderKind::Claude);
    }

    if env::var(OPENAI_KEY).is_ok() {
        eprintln!("[detector] Detected provider: OpenAI (environment variable)");
        found.push(AiProviderKind::OpenAi);
    }

    if env::var("OLLAMA_HOST").is_ok() || env::var("OLLAMA_URL").is_ok() {
        eprintln!("[detector] Detected provider: Ollama (environment variable)");
        found.push(AiProviderKind::Ollama);
    }

    found
}
