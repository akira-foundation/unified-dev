use std::env;

use reqwest::Client;
use serde::Deserialize;

use super::{AiModel, AiProviderKind};

#[derive(Deserialize)]
struct OpenAiModelsResponse {
    data: Vec<OpenAiModelEntry>,
}

#[derive(Deserialize)]
struct OpenAiModelEntry {
    id: String,
}

#[derive(Deserialize)]
struct OllamaTagsResponse {
    models: Vec<OllamaModelEntry>,
}

#[derive(Deserialize)]
struct OllamaModelEntry {
    name: String,
}

pub async fn discover_openai_models() -> Result<Vec<AiModel>, String> {
    let api_key = env::var("OPENAI_API_KEY").map_err(|_| "OPENAI_API_KEY not set".to_string())?;

    let client = Client::new();
    let response = client
        .get("https://api.openai.com/v1/models")
        .header("Authorization", format!("Bearer {api_key}"))
        .send()
        .await
        .map_err(|e| format!("OpenAI request failed: {e}"))?;

    let body: OpenAiModelsResponse = response
        .json()
        .await
        .map_err(|e| format!("OpenAI response parse failed: {e}"))?;

    let models: Vec<AiModel> = body
        .data
        .into_iter()
        .filter(|m| m.id.contains("gpt"))
        .map(|m| {
            let label = m.id.replace('-', " ");
            let label = label
                .split_whitespace()
                .map(|w| {
                    let mut chars = w.chars();
                    match chars.next() {
                        Some(c) => c.to_uppercase().to_string() + chars.as_str(),
                        None => String::new(),
                    }
                })
                .collect::<Vec<_>>()
                .join(" ");

            AiModel {
                id: m.id,
                label,
                capabilities: vec![
                    "tool_use".to_string(),
                    "streaming".to_string(),
                ],
            }
        })
        .collect();

    Ok(models)
}

pub async fn discover_ollama_models() -> Result<Vec<AiModel>, String> {
    let host = env::var("OLLAMA_HOST")
        .or_else(|_| env::var("OLLAMA_URL"))
        .unwrap_or_else(|_| "http://localhost:11434".to_string());

    let url = format!("{host}/api/tags");
    let client = Client::new();

    let response = client
        .get(&url)
        .send()
        .await
        .map_err(|e| format!("Ollama request failed: {e}"))?;

    let body: OllamaTagsResponse = response
        .json()
        .await
        .map_err(|e| format!("Ollama response parse failed: {e}"))?;

    let models: Vec<AiModel> = body
        .models
        .into_iter()
        .map(|m| {
            let label = m.name.split(':').next().unwrap_or(&m.name).to_string();
            let label = label
                .split('-')
                .map(|w| {
                    let mut chars = w.chars();
                    match chars.next() {
                        Some(c) => c.to_uppercase().to_string() + chars.as_str(),
                        None => String::new(),
                    }
                })
                .collect::<Vec<_>>()
                .join(" ");

            AiModel {
                id: m.name,
                label,
                capabilities: vec!["streaming".to_string()],
            }
        })
        .collect();

    Ok(models)
}

pub fn fallback_models(kind: &AiProviderKind) -> Vec<AiModel> {
    match kind {
        AiProviderKind::Claude => vec![
            AiModel {
                id: "claude-sonnet".to_string(),
                label: "Claude Sonnet".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string(), "reasoning".to_string()],
            },
            AiModel {
                id: "claude-opus".to_string(),
                label: "Claude Opus".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string(), "reasoning".to_string()],
            },
            AiModel {
                id: "claude-haiku".to_string(),
                label: "Claude Haiku".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
        ],
        AiProviderKind::OpenAi => vec![
            AiModel {
                id: "gpt-5.3-codex".to_string(),
                label: "GPT 5.3 Codex".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "gpt-5.4".to_string(),
                label: "GPT 5.4".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string(), "reasoning".to_string()],
            },
            AiModel {
                id: "gpt-5.2".to_string(),
                label: "GPT 5.2".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "gpt-5.1-codex-mini".to_string(),
                label: "GPT 5.1 Codex Mini".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
        ],
        AiProviderKind::Copilot => vec![
            AiModel {
                id: "copilot-gpt-4o".to_string(),
                label: "Copilot GPT-4o".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
            AiModel {
                id: "copilot-claude-sonnet".to_string(),
                label: "Copilot Claude Sonnet".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string(), "reasoning".to_string()],
            },
            AiModel {
                id: "copilot-gemini-pro".to_string(),
                label: "Copilot Gemini Pro".to_string(),
                capabilities: vec!["tool_use".to_string(), "streaming".to_string()],
            },
        ],
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
