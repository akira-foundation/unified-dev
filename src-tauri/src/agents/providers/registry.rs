use std::fs;
use std::path::PathBuf;

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use super::detector::detect_providers;
use super::discovery::{discover_ollama_models, discover_openai_models, fallback_models};
use super::{AiProviderGroup, AiProviderKind};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelRegistry {
    pub providers: Vec<AiProviderGroup>,
    pub last_updated: DateTime<Utc>,
}

fn cache_path() -> Option<PathBuf> {
    dirs::home_dir().map(|home| home.join(".unifieddev").join("model_registry.json"))
}

fn load_cached_registry() -> Option<ModelRegistry> {
    let path = cache_path()?;
    let content = fs::read_to_string(&path).ok()?;
    let registry: ModelRegistry = serde_json::from_str(&content).ok()?;

    let age = Utc::now() - registry.last_updated;
    if age < Duration::hours(1) {
        Some(registry)
    } else {
        None
    }
}

fn save_registry_cache(registry: &ModelRegistry) {
    if let Some(path) = cache_path() {
        if let Some(parent) = path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        if let Ok(json) = serde_json::to_string_pretty(registry) {
            let _ = fs::write(&path, json);
        }
    }
}

pub async fn build_model_registry() -> ModelRegistry {
    let detected = detect_providers().await;
    let mut provider_groups: Vec<AiProviderGroup> = Vec::new();

    for kind in &detected {
        let models = match kind {
            AiProviderKind::OpenAi => {
                discover_openai_models()
                    .await
                    .unwrap_or_else(|_| fallback_models(kind))
            }
            AiProviderKind::Ollama => {
                discover_ollama_models()
                    .await
                    .unwrap_or_else(|_| fallback_models(kind))
            }
            AiProviderKind::Claude => fallback_models(kind),
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
