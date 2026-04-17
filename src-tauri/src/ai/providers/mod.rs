pub mod anthropic;
pub mod copilot;
pub mod google;
pub mod openai;

use std::sync::Arc;

use crate::ai::registry::AiRegistry;

pub fn default_registry() -> AiRegistry {
    let mut registry = AiRegistry::new();
    registry.register(Arc::new(anthropic::AnthropicProvider));
    registry.register(Arc::new(anthropic::AnthropicCliProvider));
    registry.register(Arc::new(openai::OpenAiProvider));
    registry.register(Arc::new(openai::OpenAiCliProvider));
    registry.register(Arc::new(copilot::CopilotChatProvider));
    registry.register(Arc::new(copilot::CopilotResponsesProvider));
    registry.register(Arc::new(google::GeminiCliProvider));
    registry
}
