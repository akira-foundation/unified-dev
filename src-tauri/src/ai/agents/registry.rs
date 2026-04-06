use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::cache::{load_cached_registry, save_registry_cache};
use super::detector::detect_providers;
use super::discovery::fallback_models;
use super::types::{AiProviderGroup, AiProviderKind};
use crate::ai::credentials::{read_copilot_oauth_token, resolve_env_key};
use crate::ai::providers::anthropic::find_claude_cli;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelRegistry {
    pub providers: Vec<AiProviderGroup>,
    pub last_updated: DateTime<Utc>,
}

pub async fn build_model_registry() -> ModelRegistry {
    let detected = detect_providers().await;
    let has_anthropic_key = resolve_env_key("ANTHROPIC_API_KEY").is_some();
    let has_claude_cli = find_claude_cli().is_some();
    let has_copilot = read_copilot_oauth_token().is_some();

    let mut provider_groups: Vec<AiProviderGroup> = Vec::new();

    if has_anthropic_key || has_claude_cli || has_copilot {
        let claude_models = fallback_models(&AiProviderKind::Claude);

        if has_anthropic_key || has_claude_cli {
            provider_groups.push(AiProviderGroup {
                name: "Claude".to_string(),
                models: claude_models.clone(),
            });
        }

        if has_copilot {
            let copilot_models = claude_models
                .into_iter()
                .map(|m| super::types::AiModel {
                    id: format!("copilot:{}", m.id),
                    ..m
                })
                .collect();
            provider_groups.push(AiProviderGroup {
                name: "GitHub Copilot".to_string(),
                models: copilot_models,
            });
        }
    }

    for kind in detected.iter().filter(|k| matches!(k, AiProviderKind::OpenAi)) {
        let models = super::discovery::discover_codex_models()
            .unwrap_or_else(|_| fallback_models(kind));

        if models.is_empty() {
            continue;
        }

        provider_groups.push(AiProviderGroup {
            name: kind.display_name().to_string(),
            models,
        });
    }

    let registry = ModelRegistry {
        providers: provider_groups,
        last_updated: Utc::now(),
    };

    save_registry_cache(&registry);

    registry
}

pub async fn get_or_build_registry() -> ModelRegistry {
    if let Some(cached) = load_cached_registry() {
        return cached;
    }

    build_model_registry().await
}
