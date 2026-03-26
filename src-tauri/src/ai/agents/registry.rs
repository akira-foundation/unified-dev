use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use super::cache::{load_cached_registry, save_registry_cache};
use super::detector::detect_providers;
use super::discovery::fallback_models;
use super::types::{AiProviderGroup, AiProviderKind};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelRegistry {
    pub providers: Vec<AiProviderGroup>,
    pub last_updated: DateTime<Utc>,
}

pub async fn build_model_registry() -> ModelRegistry {
    let detected = detect_providers().await;

    let mut provider_groups: Vec<AiProviderGroup> = Vec::new();

    for kind in detected.iter().filter(|k| matches!(k, AiProviderKind::OpenAi | AiProviderKind::Claude)) {
        let models = match kind {
            AiProviderKind::OpenAi => {
                super::discovery::discover_codex_models()
                    .unwrap_or_else(|_| fallback_models(kind))
            }
            AiProviderKind::Claude => fallback_models(kind),
            _ => continue,
        };

        if !models.is_empty() {
            provider_groups.push(AiProviderGroup {
                name: kind.display_name().to_string(),
                models,
            });
        }
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
