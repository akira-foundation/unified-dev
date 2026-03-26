use crate::ai::agents::types::AiModel;

pub fn fallback_models() -> Vec<AiModel> {
    vec![AiModel {
        id: "gpt-4o".to_string(),
        label: "GPT-4o".to_string(),
        capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
    }]
}
