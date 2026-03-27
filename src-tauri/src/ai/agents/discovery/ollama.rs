use crate::ai::agents::types::AiModel;

pub fn fallback_models() -> Vec<AiModel> {
    vec![
        AiModel {
            id: "llama3".to_string(),
            label: "Llama 3".to_string(),
            capabilities: vec!["streaming".to_string()],
            context_window: 8_192,
        },
        AiModel {
            id: "codellama".to_string(),
            label: "Code Llama".to_string(),
            capabilities: vec!["streaming".to_string()],
            context_window: 16_384,
        },
        AiModel {
            id: "deepseek-coder".to_string(),
            label: "DeepSeek Coder".to_string(),
            capabilities: vec!["streaming".to_string()],
            context_window: 16_384,
        },
    ]
}
