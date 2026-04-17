mod anthropic;
mod copilot;
mod gemini;
mod ollama;
mod openai;

pub use openai::discover_codex_models;

use crate::ai::agents::types::{AiModel, AiProviderKind};

pub fn fallback_models(kind: &AiProviderKind) -> Vec<AiModel> {
    match kind {
        AiProviderKind::Claude => anthropic::fallback_models(),
        AiProviderKind::Gemini => gemini::fallback_models(),
        AiProviderKind::OpenAi => openai::fallback_models(),
        AiProviderKind::Copilot => copilot::fallback_models(),
        AiProviderKind::Ollama => ollama::fallback_models(),
    }
}
