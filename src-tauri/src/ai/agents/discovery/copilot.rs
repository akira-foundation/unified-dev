use crate::ai::agents::types::AiModel;

pub fn fallback_models() -> Vec<AiModel> {
    vec![
        AiModel {
            id: "claude-sonnet-4.6".to_string(),
            label: "Sonnet".to_string(),
            capabilities: vec![
                "tool_use".to_string(),
                "streaming".to_string(),
                "vision".to_string(),
            ],
            context_window: 200_000,
        },
        AiModel {
            id: "claude-opus-4.6".to_string(),
            label: "Opus".to_string(),
            capabilities: vec![
                "tool_use".to_string(),
                "streaming".to_string(),
                "vision".to_string(),
            ],
            context_window: 144_000,
        },
        AiModel {
            id: "claude-haiku-4.5".to_string(),
            label: "Haiku".to_string(),
            capabilities: vec![
                "tool_use".to_string(),
                "streaming".to_string(),
                "vision".to_string(),
            ],
            context_window: 144_000,
        },
        AiModel {
            id: "gpt-4o".to_string(),
            label: "GPT-4o".to_string(),
            capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            context_window: 128_000,
        },
    ]
}
