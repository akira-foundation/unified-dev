use crate::ai::agents::types::AiModel;

pub fn fallback_models() -> Vec<AiModel> {
    vec![
        AiModel {
            id: "gemini-3.1-pro-preview".to_string(),
            label: "Gemini 3.1 Pro".to_string(),
            capabilities: vec![
                "tool_use".to_string(),
                "streaming".to_string(),
                "reasoning".to_string(),
            ],
            context_window: 1_000_000,
        },
        AiModel {
            id: "gemini-3-pro-preview".to_string(),
            label: "Gemini 3 Pro".to_string(),
            capabilities: vec![
                "tool_use".to_string(),
                "streaming".to_string(),
                "reasoning".to_string(),
            ],
            context_window: 1_000_000,
        },
        AiModel {
            id: "gemini-3-flash-preview".to_string(),
            label: "Gemini 3 Flash".to_string(),
            capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            context_window: 1_000_000,
        },
        AiModel {
            id: "gemini-2.5-pro".to_string(),
            label: "Gemini 2.5 Pro".to_string(),
            capabilities: vec![
                "tool_use".to_string(),
                "streaming".to_string(),
                "reasoning".to_string(),
            ],
            context_window: 1_000_000,
        },
        AiModel {
            id: "gemini-2.5-flash".to_string(),
            label: "Gemini 2.5 Flash".to_string(),
            capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            context_window: 1_000_000,
        },
        AiModel {
            id: "gemini-2.5-flash-lite".to_string(),
            label: "Gemini 2.5 Flash Lite".to_string(),
            capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            context_window: 1_000_000,
        },
    ]
}
