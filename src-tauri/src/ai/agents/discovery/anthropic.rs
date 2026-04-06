use crate::ai::agents::types::AiModel;

pub fn fallback_models() -> Vec<AiModel> {
    vec![
        AiModel {
            id: "claude-sonnet-latest".to_string(),
            label: "Sonnet".to_string(),
            capabilities: vec![
                "tool_use".to_string(),
                "streaming".to_string(),
                "reasoning".to_string(),
            ],
            context_window: 200_000,
        },
        AiModel {
            id: "claude-opus-latest".to_string(),
            label: "Opus".to_string(),
            capabilities: vec![
                "tool_use".to_string(),
                "streaming".to_string(),
                "reasoning".to_string(),
            ],
            context_window: 200_000,
        },
        AiModel {
            id: "claude-haiku-latest".to_string(),
            label: "Haiku".to_string(),
            capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            context_window: 200_000,
        },
    ]
}
