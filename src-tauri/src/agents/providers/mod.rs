pub mod detector;
pub mod discovery;
pub mod registry;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub enum AiProviderKind {
    Claude,
    OpenAi,
    Copilot,
    Ollama,
}

impl AiProviderKind {
    pub fn display_name(&self) -> &str {
        match self {
            AiProviderKind::Claude => "Claude",
            AiProviderKind::OpenAi => "Codex",
            AiProviderKind::Copilot => "Copilot",
            AiProviderKind::Ollama => "Ollama",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiModel {
    pub id: String,
    pub label: String,
    pub capabilities: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AiProviderGroup {
    pub name: String,
    pub models: Vec<AiModel>,
}
