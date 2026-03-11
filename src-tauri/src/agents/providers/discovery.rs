use serde::Deserialize;

use super::{AiModel, AiProviderKind};

// ---------------------------------------------------------------------------
// Codex CLI local model cache
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct CodexModelsCache {
    models: Vec<CodexModelEntry>,
}

#[derive(Deserialize)]
struct CodexModelEntry {
    slug: String,
    display_name: String,
    #[serde(default)]
    supported_in_api: bool,
    #[serde(default)]
    visibility: String,
}

/// Reads the Codex model list from `~/.codex/models_cache.json`.
/// No network call needed — the Codex CLI maintains this cache locally.
pub fn discover_codex_models() -> Result<Vec<AiModel>, String> {
    let home = dirs::home_dir().ok_or("no home dir")?;
    let path = home.join(".codex/models_cache.json");
    let content =
        std::fs::read_to_string(&path).map_err(|e| format!("read models_cache.json: {e}"))?;
    let cache: CodexModelsCache =
        serde_json::from_str(&content).map_err(|e| format!("parse models_cache.json: {e}"))?;

    let models = cache
        .models
        .into_iter()
        .filter(|m| m.supported_in_api && (m.visibility == "list" || m.visibility.is_empty()))
        .map(|m| AiModel {
            id: m.slug,
            label: m.display_name,
            capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
        })
        .collect();

    Ok(models)
}

pub fn fallback_models(kind: &AiProviderKind) -> Vec<AiModel> {
    match kind {
        AiProviderKind::Claude => vec![
            AiModel {
                id: "claude-sonnet-latest".to_string(),
                label: "Claude Sonnet".to_string(),
                capabilities: vec![
                    "tool_use".to_string(),
                    "streaming".to_string(),
                    "reasoning".to_string(),
                ],
            },
            AiModel {
                id: "claude-opus-latest".to_string(),
                label: "Claude Opus".to_string(),
                capabilities: vec![
                    "tool_use".to_string(),
                    "streaming".to_string(),
                    "reasoning".to_string(),
                ],
            },
            AiModel {
                id: "claude-haiku-latest".to_string(),
                label: "Claude Haiku".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
        ],
        AiProviderKind::OpenAi => vec![
            AiModel {
                id: "gpt-5.4".to_string(),
                label: "gpt-5.4".to_string(),
                capabilities: vec![
                    "tool_use".to_string(),
                    "streaming".to_string(),
                    "reasoning".to_string(),
                ],
            },
            AiModel {
                id: "gpt-5.3-codex".to_string(),
                label: "gpt-5.3-codex".to_string(),
                capabilities: vec![
                    "tool_use".to_string(),
                    "streaming".to_string(),
                    "reasoning".to_string(),
                ],
            },
            AiModel {
                id: "gpt-5.2-codex".to_string(),
                label: "gpt-5.2-codex".to_string(),
                capabilities: vec![
                    "tool_use".to_string(),
                    "streaming".to_string(),
                    "reasoning".to_string(),
                ],
            },
            AiModel {
                id: "gpt-5.2".to_string(),
                label: "gpt-5.2".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "gpt-5.1-codex-max".to_string(),
                label: "gpt-5.1-codex-max".to_string(),
                capabilities: vec![
                    "tool_use".to_string(),
                    "streaming".to_string(),
                    "reasoning".to_string(),
                ],
            },
            AiModel {
                id: "gpt-5.1-codex".to_string(),
                label: "gpt-5.1-codex".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "gpt-5.1".to_string(),
                label: "gpt-5.1".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "gpt-5-codex".to_string(),
                label: "gpt-5-codex".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "gpt-5".to_string(),
                label: "gpt-5".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "gpt-5.1-codex-mini".to_string(),
                label: "gpt-5.1-codex-mini".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "gpt-5-codex-mini".to_string(),
                label: "gpt-5-codex-mini".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
        ],
        AiProviderKind::Copilot => vec![AiModel {
            id: "gpt-4o".to_string(),
            label: "GPT-4o".to_string(),
            capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
        }],
        AiProviderKind::Ollama => vec![
            AiModel {
                id: "llama3".to_string(),
                label: "Llama 3".to_string(),
                capabilities: vec!["streaming".to_string()],
            },
            AiModel {
                id: "codellama".to_string(),
                label: "Code Llama".to_string(),
                capabilities: vec!["streaming".to_string()],
            },
            AiModel {
                id: "deepseek-coder".to_string(),
                label: "DeepSeek Coder".to_string(),
                capabilities: vec!["streaming".to_string()],
            },
        ],
    }
}
